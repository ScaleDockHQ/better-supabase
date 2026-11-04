-- better-supabase module: audit
-- @bsb-block-test audit
-- @bsb-hash sha256:9166a314c1edb17abd615de33d843e629cb01a6448aef9ec8bc660dbbe3ddd59
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(1225);

create temp table bsb_audit_probe (like "better_supabase"."access_requests" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'access_requests', 'bsb_audit', 'better_supabase.access_requests has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'access_requests', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.access_requests calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."access_requests"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.access_requests is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."access_requests"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.access_requests is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.access_requests write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."accounting_accounts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'accounting_accounts', 'bsb_audit', 'better_supabase.accounting_accounts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'accounting_accounts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.accounting_accounts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."accounting_accounts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.accounting_accounts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."accounting_accounts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.accounting_accounts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.accounting_accounts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."accounting_budgets" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'accounting_budgets', 'bsb_audit', 'better_supabase.accounting_budgets has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'accounting_budgets', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.accounting_budgets calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."accounting_budgets"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.accounting_budgets is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."accounting_budgets"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.accounting_budgets is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.accounting_budgets write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."accounting_dimensions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'accounting_dimensions', 'bsb_audit', 'better_supabase.accounting_dimensions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'accounting_dimensions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.accounting_dimensions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."accounting_dimensions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.accounting_dimensions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."accounting_dimensions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.accounting_dimensions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.accounting_dimensions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."accounting_entries" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'accounting_entries', 'bsb_audit', 'better_supabase.accounting_entries has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'accounting_entries', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.accounting_entries calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."accounting_entries"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.accounting_entries is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."accounting_entries"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.accounting_entries is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.accounting_entries write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."accounting_journals" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'accounting_journals', 'bsb_audit', 'better_supabase.accounting_journals has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'accounting_journals', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.accounting_journals calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."accounting_journals"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.accounting_journals is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."accounting_journals"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.accounting_journals is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.accounting_journals write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."accounting_periods" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'accounting_periods', 'bsb_audit', 'better_supabase.accounting_periods has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'accounting_periods', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.accounting_periods calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."accounting_periods"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.accounting_periods is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."accounting_periods"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.accounting_periods is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.accounting_periods write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."acknowledgement_assignments" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'acknowledgement_assignments', 'bsb_audit', 'better_supabase.acknowledgement_assignments has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'acknowledgement_assignments', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.acknowledgement_assignments calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."acknowledgement_assignments"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.acknowledgement_assignments is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."acknowledgement_assignments"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.acknowledgement_assignments is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.acknowledgement_assignments write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."acknowledgements" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'acknowledgements', 'bsb_audit', 'better_supabase.acknowledgements has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'acknowledgements', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.acknowledgements calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."acknowledgements"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.acknowledgements is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."acknowledgements"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.acknowledgements is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.acknowledgements write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."activities" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'activities', 'bsb_audit', 'better_supabase.activities has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'activities', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.activities calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."activities"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.activities is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."activities"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.activities is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.activities write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."agents" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'agents', 'bsb_audit', 'better_supabase.agents has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'agents', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.agents calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."agents"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.agents is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."agents"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.agents is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.agents write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."ai_chats" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'ai_chats', 'bsb_audit', 'better_supabase.ai_chats has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'ai_chats', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.ai_chats calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ai_chats"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.ai_chats is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ai_chats"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.ai_chats is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.ai_chats write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."ai_documents" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'ai_documents', 'bsb_audit', 'better_supabase.ai_documents has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'ai_documents', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.ai_documents calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ai_documents"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.ai_documents is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ai_documents"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.ai_documents is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.ai_documents write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."ai_projects" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'ai_projects', 'bsb_audit', 'better_supabase.ai_projects has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'ai_projects', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.ai_projects calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ai_projects"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.ai_projects is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ai_projects"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.ai_projects is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.ai_projects write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."ai_scheduled_tasks" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'ai_scheduled_tasks', 'bsb_audit', 'better_supabase.ai_scheduled_tasks has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'ai_scheduled_tasks', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.ai_scheduled_tasks calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ai_scheduled_tasks"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.ai_scheduled_tasks is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ai_scheduled_tasks"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.ai_scheduled_tasks is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.ai_scheduled_tasks write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."announcements" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'announcements', 'bsb_audit', 'better_supabase.announcements has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'announcements', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.announcements calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."announcements"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.announcements is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."announcements"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.announcements is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.announcements write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."api_keys" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'api_keys', 'bsb_audit', 'better_supabase.api_keys has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'api_keys', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.api_keys calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."api_keys"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.api_keys is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."api_keys"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.api_keys is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.api_keys write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."applications" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'applications', 'bsb_audit', 'better_supabase.applications has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'applications', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.applications calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."applications"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.applications is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."applications"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.applications is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.applications write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."appraisal_calibrations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'appraisal_calibrations', 'bsb_audit', 'better_supabase.appraisal_calibrations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'appraisal_calibrations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.appraisal_calibrations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisal_calibrations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.appraisal_calibrations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisal_calibrations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.appraisal_calibrations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.appraisal_calibrations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."appraisal_competencies" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'appraisal_competencies', 'bsb_audit', 'better_supabase.appraisal_competencies has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'appraisal_competencies', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.appraisal_competencies calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisal_competencies"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.appraisal_competencies is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisal_competencies"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.appraisal_competencies is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.appraisal_competencies write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."appraisal_cycles" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'appraisal_cycles', 'bsb_audit', 'better_supabase.appraisal_cycles has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'appraisal_cycles', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.appraisal_cycles calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisal_cycles"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.appraisal_cycles is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisal_cycles"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.appraisal_cycles is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.appraisal_cycles write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."appraisal_goals" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'appraisal_goals', 'bsb_audit', 'better_supabase.appraisal_goals has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'appraisal_goals', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.appraisal_goals calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisal_goals"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.appraisal_goals is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisal_goals"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.appraisal_goals is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.appraisal_goals write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."appraisal_review_ratings" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'appraisal_review_ratings', 'bsb_audit', 'better_supabase.appraisal_review_ratings has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'appraisal_review_ratings', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.appraisal_review_ratings calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisal_review_ratings"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.appraisal_review_ratings is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisal_review_ratings"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.appraisal_review_ratings is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.appraisal_review_ratings write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."appraisal_reviews" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'appraisal_reviews', 'bsb_audit', 'better_supabase.appraisal_reviews has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'appraisal_reviews', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.appraisal_reviews calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisal_reviews"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.appraisal_reviews is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisal_reviews"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.appraisal_reviews is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.appraisal_reviews write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."appraisals" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'appraisals', 'bsb_audit', 'better_supabase.appraisals has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'appraisals', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.appraisals calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisals"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.appraisals is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."appraisals"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.appraisals is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.appraisals write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."approval_requests" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'approval_requests', 'bsb_audit', 'better_supabase.approval_requests has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'approval_requests', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.approval_requests calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."approval_requests"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.approval_requests is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."approval_requests"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.approval_requests is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.approval_requests write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."asset_locations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'asset_locations', 'bsb_audit', 'better_supabase.asset_locations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'asset_locations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.asset_locations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."asset_locations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.asset_locations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."asset_locations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.asset_locations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.asset_locations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."assets" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'assets', 'bsb_audit', 'better_supabase.assets has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'assets', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.assets calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."assets"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.assets is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."assets"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.assets is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.assets write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."assignment_queues" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'assignment_queues', 'bsb_audit', 'better_supabase.assignment_queues has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'assignment_queues', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.assignment_queues calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."assignment_queues"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.assignment_queues is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."assignment_queues"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.assignment_queues is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.assignment_queues write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."attachments" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'attachments', 'bsb_audit', 'better_supabase.attachments has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'attachments', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.attachments calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."attachments"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.attachments is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."attachments"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.attachments is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.attachments write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."automations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'automations', 'bsb_audit', 'better_supabase.automations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'automations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.automations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."automations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.automations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."automations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.automations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.automations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."bank_accounts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'bank_accounts', 'bsb_audit', 'better_supabase.bank_accounts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'bank_accounts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.bank_accounts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bank_accounts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.bank_accounts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bank_accounts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.bank_accounts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.bank_accounts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."bank_matches" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'bank_matches', 'bsb_audit', 'better_supabase.bank_matches has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'bank_matches', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.bank_matches calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bank_matches"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.bank_matches is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bank_matches"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.bank_matches is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.bank_matches write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."bank_rules" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'bank_rules', 'bsb_audit', 'better_supabase.bank_rules has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'bank_rules', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.bank_rules calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bank_rules"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.bank_rules is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bank_rules"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.bank_rules is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.bank_rules write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."bank_statements" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'bank_statements', 'bsb_audit', 'better_supabase.bank_statements has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'bank_statements', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.bank_statements calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bank_statements"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.bank_statements is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bank_statements"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.bank_statements is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.bank_statements write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."bank_transactions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'bank_transactions', 'bsb_audit', 'better_supabase.bank_transactions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'bank_transactions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.bank_transactions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bank_transactions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.bank_transactions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bank_transactions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.bank_transactions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.bank_transactions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."bin_slots" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'bin_slots', 'bsb_audit', 'better_supabase.bin_slots has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'bin_slots', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.bin_slots calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bin_slots"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.bin_slots is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bin_slots"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.bin_slots is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.bin_slots write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."bom_components" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'bom_components', 'bsb_audit', 'better_supabase.bom_components has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'bom_components', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.bom_components calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bom_components"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.bom_components is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bom_components"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.bom_components is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.bom_components write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."bom_operations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'bom_operations', 'bsb_audit', 'better_supabase.bom_operations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'bom_operations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.bom_operations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bom_operations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.bom_operations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bom_operations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.bom_operations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.bom_operations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."boms" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'boms', 'bsb_audit', 'better_supabase.boms has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'boms', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.boms calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."boms"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.boms is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."boms"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.boms is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.boms write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."bookings" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'bookings', 'bsb_audit', 'better_supabase.bookings has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'bookings', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.bookings calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bookings"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.bookings is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."bookings"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.bookings is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.bookings write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."calendar_events" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'calendar_events', 'bsb_audit', 'better_supabase.calendar_events has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'calendar_events', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.calendar_events calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."calendar_events"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.calendar_events is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."calendar_events"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.calendar_events is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.calendar_events write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."calendars" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'calendars', 'bsb_audit', 'better_supabase.calendars has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'calendars', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.calendars calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."calendars"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.calendars is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."calendars"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.calendars is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.calendars write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."care_alerts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'care_alerts', 'bsb_audit', 'better_supabase.care_alerts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'care_alerts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.care_alerts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_alerts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.care_alerts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_alerts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.care_alerts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.care_alerts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."care_plan_actions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'care_plan_actions', 'bsb_audit', 'better_supabase.care_plan_actions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'care_plan_actions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.care_plan_actions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_plan_actions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.care_plan_actions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_plan_actions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.care_plan_actions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.care_plan_actions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."care_plan_evaluations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'care_plan_evaluations', 'bsb_audit', 'better_supabase.care_plan_evaluations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'care_plan_evaluations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.care_plan_evaluations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_plan_evaluations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.care_plan_evaluations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_plan_evaluations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.care_plan_evaluations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.care_plan_evaluations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."care_plan_goals" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'care_plan_goals', 'bsb_audit', 'better_supabase.care_plan_goals has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'care_plan_goals', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.care_plan_goals calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_plan_goals"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.care_plan_goals is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_plan_goals"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.care_plan_goals is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.care_plan_goals write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."care_plan_problems" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'care_plan_problems', 'bsb_audit', 'better_supabase.care_plan_problems has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'care_plan_problems', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.care_plan_problems calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_plan_problems"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.care_plan_problems is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_plan_problems"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.care_plan_problems is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.care_plan_problems write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."care_plans" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'care_plans', 'bsb_audit', 'better_supabase.care_plans has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'care_plans', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.care_plans calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_plans"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.care_plans is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_plans"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.care_plans is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.care_plans write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."care_rules" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'care_rules', 'bsb_audit', 'better_supabase.care_rules has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'care_rules', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.care_rules calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_rules"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.care_rules is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."care_rules"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.care_rules is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.care_rules write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."carts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'carts', 'bsb_audit', 'better_supabase.carts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'carts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.carts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."carts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.carts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."carts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.carts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.carts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."case_actions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'case_actions', 'bsb_audit', 'better_supabase.case_actions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'case_actions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.case_actions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."case_actions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.case_actions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."case_actions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.case_actions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.case_actions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."case_kinds" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'case_kinds', 'bsb_audit', 'better_supabase.case_kinds has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'case_kinds', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.case_kinds calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."case_kinds"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.case_kinds is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."case_kinds"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.case_kinds is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.case_kinds write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."cases" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'cases', 'bsb_audit', 'better_supabase.cases has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'cases', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.cases calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."cases"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.cases is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."cases"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.cases is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.cases write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."channels" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'channels', 'bsb_audit', 'better_supabase.channels has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'channels', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.channels calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."channels"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.channels is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."channels"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.channels is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.channels write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."commission_assignments" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'commission_assignments', 'bsb_audit', 'better_supabase.commission_assignments has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'commission_assignments', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.commission_assignments calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."commission_assignments"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.commission_assignments is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."commission_assignments"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.commission_assignments is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.commission_assignments write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."commission_plans" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'commission_plans', 'bsb_audit', 'better_supabase.commission_plans has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'commission_plans', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.commission_plans calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."commission_plans"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.commission_plans is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."commission_plans"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.commission_plans is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.commission_plans write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."commission_statements" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'commission_statements', 'bsb_audit', 'better_supabase.commission_statements has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'commission_statements', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.commission_statements calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."commission_statements"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.commission_statements is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."commission_statements"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.commission_statements is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.commission_statements write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."commissions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'commissions', 'bsb_audit', 'better_supabase.commissions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'commissions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.commissions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."commissions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.commissions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."commissions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.commissions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.commissions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."companies" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'companies', 'bsb_audit', 'better_supabase.companies has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'companies', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.companies calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."companies"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.companies is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."companies"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.companies is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.companies write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."compliance_policies" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'compliance_policies', 'bsb_audit', 'better_supabase.compliance_policies has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'compliance_policies', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.compliance_policies calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."compliance_policies"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.compliance_policies is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."compliance_policies"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.compliance_policies is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.compliance_policies write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."connector_servers" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'connector_servers', 'bsb_audit', 'better_supabase.connector_servers has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'connector_servers', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.connector_servers calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."connector_servers"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.connector_servers is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."connector_servers"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.connector_servers is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.connector_servers write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."consent_purposes" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'consent_purposes', 'bsb_audit', 'better_supabase.consent_purposes has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'consent_purposes', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.consent_purposes calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."consent_purposes"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.consent_purposes is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."consent_purposes"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.consent_purposes is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.consent_purposes write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."consents" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'consents', 'bsb_audit', 'better_supabase.consents has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'consents', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.consents calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."consents"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.consents is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."consents"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.consents is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.consents write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."content_entries" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'content_entries', 'bsb_audit', 'better_supabase.content_entries has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'content_entries', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.content_entries calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."content_entries"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.content_entries is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."content_entries"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.content_entries is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.content_entries write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."contract_obligations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'contract_obligations', 'bsb_audit', 'better_supabase.contract_obligations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'contract_obligations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.contract_obligations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."contract_obligations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.contract_obligations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."contract_obligations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.contract_obligations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.contract_obligations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."contracts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'contracts', 'bsb_audit', 'better_supabase.contracts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'contracts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.contracts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."contracts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.contracts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."contracts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.contracts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.contracts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."control_frameworks" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'control_frameworks', 'bsb_audit', 'better_supabase.control_frameworks has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'control_frameworks', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.control_frameworks calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."control_frameworks"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.control_frameworks is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."control_frameworks"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.control_frameworks is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.control_frameworks write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."controls" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'controls', 'bsb_audit', 'better_supabase.controls has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'controls', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.controls calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."controls"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.controls is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."controls"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.controls is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.controls write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."conversations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'conversations', 'bsb_audit', 'better_supabase.conversations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'conversations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.conversations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."conversations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.conversations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."conversations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.conversations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.conversations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."count_plans" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'count_plans', 'bsb_audit', 'better_supabase.count_plans has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'count_plans', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.count_plans calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."count_plans"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.count_plans is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."count_plans"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.count_plans is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.count_plans write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."course_certificates" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'course_certificates', 'bsb_audit', 'better_supabase.course_certificates has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'course_certificates', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.course_certificates calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."course_certificates"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.course_certificates is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."course_certificates"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.course_certificates is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.course_certificates write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."course_lessons" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'course_lessons', 'bsb_audit', 'better_supabase.course_lessons has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'course_lessons', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.course_lessons calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."course_lessons"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.course_lessons is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."course_lessons"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.course_lessons is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.course_lessons write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."course_modules" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'course_modules', 'bsb_audit', 'better_supabase.course_modules has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'course_modules', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.course_modules calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."course_modules"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.course_modules is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."course_modules"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.course_modules is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.course_modules write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."courses" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'courses', 'bsb_audit', 'better_supabase.courses has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'courses', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.courses calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."courses"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.courses is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."courses"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.courses is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.courses write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."dam_renditions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'dam_renditions', 'bsb_audit', 'better_supabase.dam_renditions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'dam_renditions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.dam_renditions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."dam_renditions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.dam_renditions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."dam_renditions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.dam_renditions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.dam_renditions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."dam_usage_rights" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'dam_usage_rights', 'bsb_audit', 'better_supabase.dam_usage_rights has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'dam_usage_rights', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.dam_usage_rights calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."dam_usage_rights"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.dam_usage_rights is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."dam_usage_rights"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.dam_usage_rights is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.dam_usage_rights write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."deals" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'deals', 'bsb_audit', 'better_supabase.deals has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'deals', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.deals calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."deals"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.deals is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."deals"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.deals is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.deals write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."dispatch_routes" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'dispatch_routes', 'bsb_audit', 'better_supabase.dispatch_routes has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'dispatch_routes', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.dispatch_routes calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."dispatch_routes"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.dispatch_routes is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."dispatch_routes"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.dispatch_routes is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.dispatch_routes write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."document_suggestions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'document_suggestions', 'bsb_audit', 'better_supabase.document_suggestions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'document_suggestions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.document_suggestions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."document_suggestions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.document_suggestions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."document_suggestions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.document_suggestions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.document_suggestions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."document_templates" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'document_templates', 'bsb_audit', 'better_supabase.document_templates has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'document_templates', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.document_templates calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."document_templates"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.document_templates is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."document_templates"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.document_templates is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.document_templates write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."document_text_blocks" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'document_text_blocks', 'bsb_audit', 'better_supabase.document_text_blocks has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'document_text_blocks', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.document_text_blocks calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."document_text_blocks"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.document_text_blocks is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."document_text_blocks"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.document_text_blocks is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.document_text_blocks write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."documents" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'documents', 'bsb_audit', 'better_supabase.documents has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'documents', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.documents calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."documents"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.documents is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."documents"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.documents is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.documents write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."donation_funds" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'donation_funds', 'bsb_audit', 'better_supabase.donation_funds has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'donation_funds', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.donation_funds calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."donation_funds"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.donation_funds is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."donation_funds"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.donation_funds is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.donation_funds write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."donation_receipts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'donation_receipts', 'bsb_audit', 'better_supabase.donation_receipts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'donation_receipts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.donation_receipts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."donation_receipts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.donation_receipts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."donation_receipts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.donation_receipts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.donation_receipts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."donations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'donations', 'bsb_audit', 'better_supabase.donations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'donations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.donations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."donations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.donations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."donations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.donations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.donations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."drive_nodes" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'drive_nodes', 'bsb_audit', 'better_supabase.drive_nodes has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'drive_nodes', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.drive_nodes calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."drive_nodes"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.drive_nodes is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."drive_nodes"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.drive_nodes is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.drive_nodes write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."employees" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'employees', 'bsb_audit', 'better_supabase.employees has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'employees', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.employees calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."employees"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.employees is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."employees"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.employees is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.employees write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."enrichments" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'enrichments', 'bsb_audit', 'better_supabase.enrichments has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'enrichments', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.enrichments calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."enrichments"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.enrichments is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."enrichments"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.enrichments is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.enrichments write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."enrollment_programs" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'enrollment_programs', 'bsb_audit', 'better_supabase.enrollment_programs has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'enrollment_programs', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.enrollment_programs calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."enrollment_programs"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.enrollment_programs is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."enrollment_programs"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.enrollment_programs is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.enrollment_programs write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."enrollments" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'enrollments', 'bsb_audit', 'better_supabase.enrollments has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'enrollments', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.enrollments calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."enrollments"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.enrollments is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."enrollments"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.enrollments is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.enrollments write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."evidence_tasks" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'evidence_tasks', 'bsb_audit', 'better_supabase.evidence_tasks has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'evidence_tasks', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.evidence_tasks calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."evidence_tasks"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.evidence_tasks is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."evidence_tasks"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.evidence_tasks is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.evidence_tasks write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."expense_categories" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'expense_categories', 'bsb_audit', 'better_supabase.expense_categories has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'expense_categories', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.expense_categories calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."expense_categories"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.expense_categories is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."expense_categories"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.expense_categories is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.expense_categories write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."expense_lines" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'expense_lines', 'bsb_audit', 'better_supabase.expense_lines has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'expense_lines', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.expense_lines calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."expense_lines"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.expense_lines is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."expense_lines"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.expense_lines is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.expense_lines write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."expense_reports" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'expense_reports', 'bsb_audit', 'better_supabase.expense_reports has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'expense_reports', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.expense_reports calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."expense_reports"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.expense_reports is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."expense_reports"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.expense_reports is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.expense_reports write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."field_definitions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'field_definitions', 'bsb_audit', 'better_supabase.field_definitions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'field_definitions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.field_definitions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."field_definitions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.field_definitions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."field_definitions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.field_definitions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.field_definitions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."flags" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'flags', 'bsb_audit', 'better_supabase.flags has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'flags', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.flags calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."flags"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.flags is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."flags"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.flags is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.flags write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."forecast_snapshots" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'forecast_snapshots', 'bsb_audit', 'better_supabase.forecast_snapshots has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'forecast_snapshots', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.forecast_snapshots calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."forecast_snapshots"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.forecast_snapshots is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."forecast_snapshots"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.forecast_snapshots is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.forecast_snapshots write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."forms" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'forms', 'bsb_audit', 'better_supabase.forms has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'forms', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.forms calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."forms"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.forms is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."forms"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.forms is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.forms write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."funding_awards" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'funding_awards', 'bsb_audit', 'better_supabase.funding_awards has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'funding_awards', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.funding_awards calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."funding_awards"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.funding_awards is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."funding_awards"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.funding_awards is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.funding_awards write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."funding_claim_lines" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'funding_claim_lines', 'bsb_audit', 'better_supabase.funding_claim_lines has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'funding_claim_lines', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.funding_claim_lines calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."funding_claim_lines"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.funding_claim_lines is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."funding_claim_lines"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.funding_claim_lines is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.funding_claim_lines write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."funding_claims" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'funding_claims', 'bsb_audit', 'better_supabase.funding_claims has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'funding_claims', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.funding_claims calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."funding_claims"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.funding_claims is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."funding_claims"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.funding_claims is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.funding_claims write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."funding_deliveries" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'funding_deliveries', 'bsb_audit', 'better_supabase.funding_deliveries has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'funding_deliveries', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.funding_deliveries calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."funding_deliveries"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.funding_deliveries is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."funding_deliveries"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.funding_deliveries is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.funding_deliveries write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."funding_products" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'funding_products', 'bsb_audit', 'better_supabase.funding_products has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'funding_products', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.funding_products calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."funding_products"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.funding_products is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."funding_products"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.funding_products is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.funding_products write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."goals" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'goals', 'bsb_audit', 'better_supabase.goals has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'goals', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.goals calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."goals"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.goals is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."goals"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.goals is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.goals write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."guest_grants" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'guest_grants', 'bsb_audit', 'better_supabase.guest_grants has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'guest_grants', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.guest_grants calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."guest_grants"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.guest_grants is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."guest_grants"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.guest_grants is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.guest_grants write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."guests" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'guests', 'bsb_audit', 'better_supabase.guests has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'guests', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.guests calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."guests"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.guests is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."guests"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.guests is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.guests write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."inboxes" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'inboxes', 'bsb_audit', 'better_supabase.inboxes has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'inboxes', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.inboxes calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inboxes"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.inboxes is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inboxes"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.inboxes is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.inboxes write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."incident_postmortems" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'incident_postmortems', 'bsb_audit', 'better_supabase.incident_postmortems has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'incident_postmortems', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.incident_postmortems calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."incident_postmortems"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.incident_postmortems is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."incident_postmortems"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.incident_postmortems is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.incident_postmortems write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."incident_status_components" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'incident_status_components', 'bsb_audit', 'better_supabase.incident_status_components has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'incident_status_components', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.incident_status_components calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."incident_status_components"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.incident_status_components is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."incident_status_components"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.incident_status_components is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.incident_status_components write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."incident_status_pages" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'incident_status_pages', 'bsb_audit', 'better_supabase.incident_status_pages has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'incident_status_pages', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.incident_status_pages calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."incident_status_pages"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.incident_status_pages is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."incident_status_pages"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.incident_status_pages is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.incident_status_pages write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."incidents" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'incidents', 'bsb_audit', 'better_supabase.incidents has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'incidents', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.incidents calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."incidents"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.incidents is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."incidents"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.incidents is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.incidents write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."inspection_findings" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'inspection_findings', 'bsb_audit', 'better_supabase.inspection_findings has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'inspection_findings', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.inspection_findings calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inspection_findings"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.inspection_findings is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inspection_findings"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.inspection_findings is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.inspection_findings write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."inspection_members" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'inspection_members', 'bsb_audit', 'better_supabase.inspection_members has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'inspection_members', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.inspection_members calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inspection_members"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.inspection_members is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inspection_members"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.inspection_members is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.inspection_members write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."inspection_programs" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'inspection_programs', 'bsb_audit', 'better_supabase.inspection_programs has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'inspection_programs', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.inspection_programs calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inspection_programs"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.inspection_programs is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inspection_programs"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.inspection_programs is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.inspection_programs write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."inspections" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'inspections', 'bsb_audit', 'better_supabase.inspections has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'inspections', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.inspections calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inspections"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.inspections is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inspections"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.inspections is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.inspections write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."interviews" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'interviews', 'bsb_audit', 'better_supabase.interviews has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'interviews', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.interviews calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."interviews"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.interviews is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."interviews"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.interviews is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.interviews write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."inventory_locations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'inventory_locations', 'bsb_audit', 'better_supabase.inventory_locations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'inventory_locations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.inventory_locations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inventory_locations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.inventory_locations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inventory_locations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.inventory_locations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.inventory_locations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."inventory_receipts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'inventory_receipts', 'bsb_audit', 'better_supabase.inventory_receipts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'inventory_receipts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.inventory_receipts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inventory_receipts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.inventory_receipts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."inventory_receipts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.inventory_receipts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.inventory_receipts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."invoices" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'invoices', 'bsb_audit', 'better_supabase.invoices has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'invoices', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.invoices calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."invoices"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.invoices is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."invoices"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.invoices is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.invoices write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."iterations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'iterations', 'bsb_audit', 'better_supabase.iterations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'iterations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.iterations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."iterations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.iterations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."iterations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.iterations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.iterations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."job_openings" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'job_openings', 'bsb_audit', 'better_supabase.job_openings has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'job_openings', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.job_openings calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."job_openings"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.job_openings is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."job_openings"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.job_openings is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.job_openings write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."knowledge_documents" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'knowledge_documents', 'bsb_audit', 'better_supabase.knowledge_documents has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'knowledge_documents', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.knowledge_documents calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."knowledge_documents"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.knowledge_documents is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."knowledge_documents"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.knowledge_documents is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.knowledge_documents write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."leases" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'leases', 'bsb_audit', 'better_supabase.leases has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'leases', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.leases calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."leases"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.leases is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."leases"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.leases is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.leases write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."ledger_accounts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'ledger_accounts', 'bsb_audit', 'better_supabase.ledger_accounts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'ledger_accounts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.ledger_accounts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ledger_accounts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.ledger_accounts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ledger_accounts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.ledger_accounts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.ledger_accounts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."ledger_holds" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'ledger_holds', 'bsb_audit', 'better_supabase.ledger_holds has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'ledger_holds', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.ledger_holds calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ledger_holds"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.ledger_holds is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ledger_holds"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.ledger_holds is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.ledger_holds write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."ledger_transactions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'ledger_transactions', 'bsb_audit', 'better_supabase.ledger_transactions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'ledger_transactions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.ledger_transactions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ledger_transactions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.ledger_transactions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."ledger_transactions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.ledger_transactions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.ledger_transactions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."legal_entities" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'legal_entities', 'bsb_audit', 'better_supabase.legal_entities has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'legal_entities', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.legal_entities calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."legal_entities"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.legal_entities is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."legal_entities"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.legal_entities is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.legal_entities write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."legal_entity_settings" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'legal_entity_settings', 'bsb_audit', 'better_supabase.legal_entity_settings has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'legal_entity_settings', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.legal_entity_settings calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."legal_entity_settings"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.legal_entity_settings is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."legal_entity_settings"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.legal_entity_settings is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.legal_entity_settings write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."lims_methods" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'lims_methods', 'bsb_audit', 'better_supabase.lims_methods has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'lims_methods', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.lims_methods calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."lims_methods"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.lims_methods is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."lims_methods"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.lims_methods is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.lims_methods write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."lims_results" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'lims_results', 'bsb_audit', 'better_supabase.lims_results has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'lims_results', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.lims_results calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."lims_results"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.lims_results is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."lims_results"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.lims_results is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.lims_results write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."lims_samples" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'lims_samples', 'bsb_audit', 'better_supabase.lims_samples has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'lims_samples', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.lims_samples calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."lims_samples"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.lims_samples is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."lims_samples"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.lims_samples is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.lims_samples write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."mail_accounts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'mail_accounts', 'bsb_audit', 'better_supabase.mail_accounts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'mail_accounts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.mail_accounts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."mail_accounts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.mail_accounts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."mail_accounts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.mail_accounts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.mail_accounts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."mail_messages" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'mail_messages', 'bsb_audit', 'better_supabase.mail_messages has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'mail_messages', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.mail_messages calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."mail_messages"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.mail_messages is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."mail_messages"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.mail_messages is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.mail_messages write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."mail_threads" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'mail_threads', 'bsb_audit', 'better_supabase.mail_threads has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'mail_threads', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.mail_threads calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."mail_threads"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.mail_threads is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."mail_threads"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.mail_threads is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.mail_threads write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."maintenance_calibrations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'maintenance_calibrations', 'bsb_audit', 'better_supabase.maintenance_calibrations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'maintenance_calibrations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.maintenance_calibrations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_calibrations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.maintenance_calibrations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_calibrations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.maintenance_calibrations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.maintenance_calibrations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."maintenance_meter_readings" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'maintenance_meter_readings', 'bsb_audit', 'better_supabase.maintenance_meter_readings has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'maintenance_meter_readings', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.maintenance_meter_readings calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_meter_readings"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.maintenance_meter_readings is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_meter_readings"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.maintenance_meter_readings is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.maintenance_meter_readings write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."maintenance_meters" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'maintenance_meters', 'bsb_audit', 'better_supabase.maintenance_meters has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'maintenance_meters', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.maintenance_meters calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_meters"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.maintenance_meters is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_meters"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.maintenance_meters is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.maintenance_meters write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."maintenance_plan_parts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'maintenance_plan_parts', 'bsb_audit', 'better_supabase.maintenance_plan_parts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'maintenance_plan_parts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.maintenance_plan_parts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_plan_parts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.maintenance_plan_parts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_plan_parts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.maintenance_plan_parts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.maintenance_plan_parts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."maintenance_plans" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'maintenance_plans', 'bsb_audit', 'better_supabase.maintenance_plans has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'maintenance_plans', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.maintenance_plans calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_plans"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.maintenance_plans is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_plans"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.maintenance_plans is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.maintenance_plans write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."maintenance_request_checklist_items" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'maintenance_request_checklist_items', 'bsb_audit', 'better_supabase.maintenance_request_checklist_items has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'maintenance_request_checklist_items', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.maintenance_request_checklist_items calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_request_checklist_items"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.maintenance_request_checklist_items is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_request_checklist_items"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.maintenance_request_checklist_items is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.maintenance_request_checklist_items write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."maintenance_requests" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'maintenance_requests', 'bsb_audit', 'better_supabase.maintenance_requests has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'maintenance_requests', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.maintenance_requests calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_requests"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.maintenance_requests is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."maintenance_requests"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.maintenance_requests is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.maintenance_requests write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."medication_administrations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'medication_administrations', 'bsb_audit', 'better_supabase.medication_administrations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'medication_administrations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.medication_administrations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."medication_administrations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.medication_administrations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."medication_administrations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.medication_administrations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.medication_administrations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."medication_orders" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'medication_orders', 'bsb_audit', 'better_supabase.medication_orders has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'medication_orders', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.medication_orders calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."medication_orders"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.medication_orders is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."medication_orders"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.medication_orders is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.medication_orders write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."medications" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'medications', 'bsb_audit', 'better_supabase.medications has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'medications', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.medications calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."medications"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.medications is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."medications"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.medications is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.medications write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."meeting_action_items" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'meeting_action_items', 'bsb_audit', 'better_supabase.meeting_action_items has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'meeting_action_items', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.meeting_action_items calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."meeting_action_items"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.meeting_action_items is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."meeting_action_items"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.meeting_action_items is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.meeting_action_items write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."meeting_agenda_items" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'meeting_agenda_items', 'bsb_audit', 'better_supabase.meeting_agenda_items has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'meeting_agenda_items', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.meeting_agenda_items calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."meeting_agenda_items"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.meeting_agenda_items is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."meeting_agenda_items"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.meeting_agenda_items is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.meeting_agenda_items write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."meeting_attendees" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'meeting_attendees', 'bsb_audit', 'better_supabase.meeting_attendees has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'meeting_attendees', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.meeting_attendees calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."meeting_attendees"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.meeting_attendees is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."meeting_attendees"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.meeting_attendees is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.meeting_attendees write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."meeting_decisions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'meeting_decisions', 'bsb_audit', 'better_supabase.meeting_decisions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'meeting_decisions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.meeting_decisions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."meeting_decisions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.meeting_decisions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."meeting_decisions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.meeting_decisions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.meeting_decisions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."meetings" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'meetings', 'bsb_audit', 'better_supabase.meetings has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'meetings', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.meetings calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."meetings"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.meetings is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."meetings"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.meetings is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.meetings write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."memories" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'memories', 'bsb_audit', 'better_supabase.memories has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'memories', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.memories calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."memories"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.memories is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."memories"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.memories is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.memories write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."messages" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'messages', 'bsb_audit', 'better_supabase.messages has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'messages', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.messages calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."messages"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.messages is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."messages"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.messages is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.messages write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."moderation_items" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'moderation_items', 'bsb_audit', 'better_supabase.moderation_items has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'moderation_items', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.moderation_items calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."moderation_items"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.moderation_items is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."moderation_items"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.moderation_items is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.moderation_items write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."observation_definitions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'observation_definitions', 'bsb_audit', 'better_supabase.observation_definitions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'observation_definitions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.observation_definitions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."observation_definitions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.observation_definitions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."observation_definitions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.observation_definitions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.observation_definitions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."observations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'observations', 'bsb_audit', 'better_supabase.observations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'observations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.observations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."observations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.observations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."observations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.observations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.observations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."orders" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'orders', 'bsb_audit', 'better_supabase.orders has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'orders', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.orders calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."orders"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.orders is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."orders"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.orders is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.orders write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."pass_check_ins" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'pass_check_ins', 'bsb_audit', 'better_supabase.pass_check_ins has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'pass_check_ins', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.pass_check_ins calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."pass_check_ins"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.pass_check_ins is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."pass_check_ins"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.pass_check_ins is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.pass_check_ins write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."passes" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'passes', 'bsb_audit', 'better_supabase.passes has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'passes', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.passes calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."passes"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.passes is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."passes"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.passes is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.passes write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."payroll_lines" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'payroll_lines', 'bsb_audit', 'better_supabase.payroll_lines has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'payroll_lines', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.payroll_lines calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."payroll_lines"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.payroll_lines is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."payroll_lines"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.payroll_lines is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.payroll_lines write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."payroll_runs" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'payroll_runs', 'bsb_audit', 'better_supabase.payroll_runs has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'payroll_runs', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.payroll_runs calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."payroll_runs"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.payroll_runs is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."payroll_runs"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.payroll_runs is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.payroll_runs write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."people" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'people', 'bsb_audit', 'better_supabase.people has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'people', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.people calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."people"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.people is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."people"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.people is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.people write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."periods" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'periods', 'bsb_audit', 'better_supabase.periods has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'periods', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.periods calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."periods"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.periods is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."periods"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.periods is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.periods write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."permission_overrides" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'permission_overrides', 'bsb_audit', 'better_supabase.permission_overrides has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'permission_overrides', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.permission_overrides calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."permission_overrides"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.permission_overrides is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."permission_overrides"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.permission_overrides is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.permission_overrides write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."permissions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'permissions', 'bsb_audit', 'better_supabase.permissions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'permissions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.permissions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."permissions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.permissions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."permissions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.permissions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.permissions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."pick_lines" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'pick_lines', 'bsb_audit', 'better_supabase.pick_lines has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'pick_lines', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.pick_lines calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."pick_lines"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.pick_lines is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."pick_lines"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.pick_lines is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.pick_lines write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."pick_lists" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'pick_lists', 'bsb_audit', 'better_supabase.pick_lists has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'pick_lists', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.pick_lists calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."pick_lists"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.pick_lists is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."pick_lists"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.pick_lists is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.pick_lists write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."pick_waves" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'pick_waves', 'bsb_audit', 'better_supabase.pick_waves has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'pick_waves', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.pick_waves calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."pick_waves"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.pick_waves is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."pick_waves"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.pick_waves is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.pick_waves write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."pipelines" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'pipelines', 'bsb_audit', 'better_supabase.pipelines has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'pipelines', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.pipelines calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."pipelines"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.pipelines is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."pipelines"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.pipelines is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.pipelines write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."platform_roles" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'platform_roles', 'bsb_audit', 'better_supabase.platform_roles has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'platform_roles', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.platform_roles calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."platform_roles"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.platform_roles is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."platform_roles"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.platform_roles is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.platform_roles write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."pledges" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'pledges', 'bsb_audit', 'better_supabase.pledges has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'pledges', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.pledges calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."pledges"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.pledges is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."pledges"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.pledges is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.pledges write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."post_boards" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'post_boards', 'bsb_audit', 'better_supabase.post_boards has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'post_boards', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.post_boards calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."post_boards"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.post_boards is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."post_boards"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.post_boards is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.post_boards write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."posts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'posts', 'bsb_audit', 'better_supabase.posts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'posts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.posts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."posts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.posts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."posts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.posts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.posts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."prescriptions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'prescriptions', 'bsb_audit', 'better_supabase.prescriptions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'prescriptions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.prescriptions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."prescriptions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.prescriptions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."prescriptions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.prescriptions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.prescriptions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."product_variants" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'product_variants', 'bsb_audit', 'better_supabase.product_variants has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'product_variants', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.product_variants calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."product_variants"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.product_variants is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."product_variants"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.product_variants is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.product_variants write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."production_consumptions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'production_consumptions', 'bsb_audit', 'better_supabase.production_consumptions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'production_consumptions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.production_consumptions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."production_consumptions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.production_consumptions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."production_consumptions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.production_consumptions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.production_consumptions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."production_order_operations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'production_order_operations', 'bsb_audit', 'better_supabase.production_order_operations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'production_order_operations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.production_order_operations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."production_order_operations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.production_order_operations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."production_order_operations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.production_order_operations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.production_order_operations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."production_orders" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'production_orders', 'bsb_audit', 'better_supabase.production_orders has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'production_orders', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.production_orders calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."production_orders"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.production_orders is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."production_orders"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.production_orders is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.production_orders write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."products" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'products', 'bsb_audit', 'better_supabase.products has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'products', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.products calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."products"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.products is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."products"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.products is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.products write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."promotions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'promotions', 'bsb_audit', 'better_supabase.promotions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'promotions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.promotions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."promotions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.promotions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."promotions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.promotions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.promotions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."purchase_orders" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'purchase_orders', 'bsb_audit', 'better_supabase.purchase_orders has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'purchase_orders', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.purchase_orders calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."purchase_orders"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.purchase_orders is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."purchase_orders"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.purchase_orders is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.purchase_orders write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."purchase_requisitions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'purchase_requisitions', 'bsb_audit', 'better_supabase.purchase_requisitions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'purchase_requisitions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.purchase_requisitions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."purchase_requisitions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.purchase_requisitions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."purchase_requisitions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.purchase_requisitions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.purchase_requisitions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."putaway_rules" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'putaway_rules', 'bsb_audit', 'better_supabase.putaway_rules has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'putaway_rules', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.putaway_rules calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."putaway_rules"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.putaway_rules is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."putaway_rules"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.putaway_rules is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.putaway_rules write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."qualification_requirements" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'qualification_requirements', 'bsb_audit', 'better_supabase.qualification_requirements has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'qualification_requirements', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.qualification_requirements calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."qualification_requirements"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.qualification_requirements is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."qualification_requirements"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.qualification_requirements is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.qualification_requirements write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."qualification_types" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'qualification_types', 'bsb_audit', 'better_supabase.qualification_types has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'qualification_types', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.qualification_types calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."qualification_types"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.qualification_types is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."qualification_types"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.qualification_types is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.qualification_types write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."qualifications" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'qualifications', 'bsb_audit', 'better_supabase.qualifications has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'qualifications', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.qualifications calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."qualifications"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.qualifications is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."qualifications"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.qualifications is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.qualifications write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."quotes" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'quotes', 'bsb_audit', 'better_supabase.quotes has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'quotes', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.quotes calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."quotes"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.quotes is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."quotes"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.quotes is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.quotes write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."reactions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'reactions', 'bsb_audit', 'better_supabase.reactions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'reactions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.reactions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."reactions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.reactions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."reactions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.reactions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.reactions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."referral_codes" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'referral_codes', 'bsb_audit', 'better_supabase.referral_codes has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'referral_codes', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.referral_codes calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."referral_codes"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.referral_codes is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."referral_codes"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.referral_codes is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.referral_codes write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."referrals" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'referrals', 'bsb_audit', 'better_supabase.referrals has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'referrals', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.referrals calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."referrals"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.referrals is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."referrals"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.referrals is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.referrals write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."relations" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'relations', 'bsb_audit', 'better_supabase.relations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'relations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.relations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."relations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.relations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."relations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.relations is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.relations write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."reminders" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'reminders', 'bsb_audit', 'better_supabase.reminders has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'reminders', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.reminders calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."reminders"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.reminders is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."reminders"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.reminders is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.reminders write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."rendered_documents" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'rendered_documents', 'bsb_audit', 'better_supabase.rendered_documents has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'rendered_documents', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.rendered_documents calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."rendered_documents"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.rendered_documents is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."rendered_documents"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.rendered_documents is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.rendered_documents write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."rfq_lines" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'rfq_lines', 'bsb_audit', 'better_supabase.rfq_lines has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'rfq_lines', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.rfq_lines calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."rfq_lines"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.rfq_lines is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."rfq_lines"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.rfq_lines is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.rfq_lines write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."rfq_quote_lines" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'rfq_quote_lines', 'bsb_audit', 'better_supabase.rfq_quote_lines has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'rfq_quote_lines', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.rfq_quote_lines calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."rfq_quote_lines"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.rfq_quote_lines is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."rfq_quote_lines"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.rfq_quote_lines is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.rfq_quote_lines write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."rfq_quotes" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'rfq_quotes', 'bsb_audit', 'better_supabase.rfq_quotes has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'rfq_quotes', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.rfq_quotes calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."rfq_quotes"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.rfq_quotes is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."rfq_quotes"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.rfq_quotes is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.rfq_quotes write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."rfq_suppliers" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'rfq_suppliers', 'bsb_audit', 'better_supabase.rfq_suppliers has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'rfq_suppliers', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.rfq_suppliers calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."rfq_suppliers"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.rfq_suppliers is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."rfq_suppliers"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.rfq_suppliers is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.rfq_suppliers write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."rfqs" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'rfqs', 'bsb_audit', 'better_supabase.rfqs has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'rfqs', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.rfqs calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."rfqs"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.rfqs is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."rfqs"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.rfqs is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.rfqs write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."risk_assessments" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'risk_assessments', 'bsb_audit', 'better_supabase.risk_assessments has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'risk_assessments', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.risk_assessments calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."risk_assessments"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.risk_assessments is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."risk_assessments"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.risk_assessments is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.risk_assessments write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."risk_matrices" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'risk_matrices', 'bsb_audit', 'better_supabase.risk_matrices has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'risk_matrices', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.risk_matrices calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."risk_matrices"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.risk_matrices is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."risk_matrices"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.risk_matrices is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.risk_matrices write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."risks" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'risks', 'bsb_audit', 'better_supabase.risks has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'risks', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.risks calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."risks"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.risks is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."risks"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.risks is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.risks write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."role_permissions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'role_permissions', 'bsb_audit', 'better_supabase.role_permissions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'role_permissions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.role_permissions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."role_permissions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.role_permissions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."role_permissions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.role_permissions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.role_permissions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."roles" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'roles', 'bsb_audit', 'better_supabase.roles has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'roles', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.roles calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."roles"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.roles is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."roles"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.roles is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.roles write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."score_models" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'score_models', 'bsb_audit', 'better_supabase.score_models has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'score_models', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.score_models calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."score_models"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.score_models is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."score_models"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.score_models is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.score_models write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."segments" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'segments', 'bsb_audit', 'better_supabase.segments has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'segments', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.segments calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."segments"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.segments is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."segments"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.segments is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.segments write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."sequences" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'sequences', 'bsb_audit', 'better_supabase.sequences has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'sequences', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.sequences calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."sequences"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.sequences is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."sequences"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.sequences is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.sequences write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."share_links" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'share_links', 'bsb_audit', 'better_supabase.share_links has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'share_links', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.share_links calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."share_links"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.share_links is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."share_links"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.share_links is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.share_links write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."shared_views" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'shared_views', 'bsb_audit', 'better_supabase.shared_views has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'shared_views', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.shared_views calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shared_views"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.shared_views is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shared_views"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.shared_views is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.shared_views write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."shift_assignments" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'shift_assignments', 'bsb_audit', 'better_supabase.shift_assignments has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'shift_assignments', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.shift_assignments calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shift_assignments"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.shift_assignments is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shift_assignments"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.shift_assignments is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.shift_assignments write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."shift_availability" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'shift_availability', 'bsb_audit', 'better_supabase.shift_availability has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'shift_availability', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.shift_availability calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shift_availability"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.shift_availability is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shift_availability"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.shift_availability is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.shift_availability write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."shift_swaps" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'shift_swaps', 'bsb_audit', 'better_supabase.shift_swaps has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'shift_swaps', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.shift_swaps calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shift_swaps"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.shift_swaps is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shift_swaps"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.shift_swaps is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.shift_swaps write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."shift_templates" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'shift_templates', 'bsb_audit', 'better_supabase.shift_templates has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'shift_templates', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.shift_templates calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shift_templates"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.shift_templates is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shift_templates"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.shift_templates is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.shift_templates write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."shifts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'shifts', 'bsb_audit', 'better_supabase.shifts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'shifts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.shifts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shifts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.shifts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shifts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.shifts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.shifts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."shipment_lines" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'shipment_lines', 'bsb_audit', 'better_supabase.shipment_lines has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'shipment_lines', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.shipment_lines calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shipment_lines"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.shipment_lines is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shipment_lines"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.shipment_lines is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.shipment_lines write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."shipment_packages" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'shipment_packages', 'bsb_audit', 'better_supabase.shipment_packages has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'shipment_packages', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.shipment_packages calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shipment_packages"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.shipment_packages is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shipment_packages"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.shipment_packages is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.shipment_packages write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."shipment_tracking_events" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'shipment_tracking_events', 'bsb_audit', 'better_supabase.shipment_tracking_events has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'shipment_tracking_events', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.shipment_tracking_events calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shipment_tracking_events"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.shipment_tracking_events is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shipment_tracking_events"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.shipment_tracking_events is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.shipment_tracking_events write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."shipments" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'shipments', 'bsb_audit', 'better_supabase.shipments has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'shipments', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.shipments calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shipments"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.shipments is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."shipments"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.shipments is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.shipments write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."signature_requests" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'signature_requests', 'bsb_audit', 'better_supabase.signature_requests has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'signature_requests', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.signature_requests calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."signature_requests"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.signature_requests is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."signature_requests"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.signature_requests is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.signature_requests write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."sla_policies" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'sla_policies', 'bsb_audit', 'better_supabase.sla_policies has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'sla_policies', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.sla_policies calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."sla_policies"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.sla_policies is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."sla_policies"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.sla_policies is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.sla_policies write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."stock_lot_links" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'stock_lot_links', 'bsb_audit', 'better_supabase.stock_lot_links has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'stock_lot_links', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.stock_lot_links calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."stock_lot_links"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.stock_lot_links is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."stock_lot_links"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.stock_lot_links is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.stock_lot_links write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."tags" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'tags', 'bsb_audit', 'better_supabase.tags has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'tags', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.tags calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."tags"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.tags is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."tags"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.tags is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.tags write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."tax_codes" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'tax_codes', 'bsb_audit', 'better_supabase.tax_codes has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'tax_codes', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.tax_codes calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."tax_codes"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.tax_codes is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."tax_codes"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.tax_codes is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.tax_codes write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."tax_rates" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'tax_rates', 'bsb_audit', 'better_supabase.tax_rates has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'tax_rates', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.tax_rates calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."tax_rates"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.tax_rates is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."tax_rates"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.tax_rates is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.tax_rates write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."tax_returns" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'tax_returns', 'bsb_audit', 'better_supabase.tax_returns has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'tax_returns', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.tax_returns calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."tax_returns"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.tax_returns is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."tax_returns"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.tax_returns is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.tax_returns write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."teams" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'teams', 'bsb_audit', 'better_supabase.teams has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'teams', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.teams calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."teams"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.teams is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."teams"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.teams is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.teams write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."templates" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'templates', 'bsb_audit', 'better_supabase.templates has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'templates', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.templates calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."templates"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.templates is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."templates"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.templates is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.templates write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."till_counts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'till_counts', 'bsb_audit', 'better_supabase.till_counts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'till_counts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.till_counts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."till_counts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.till_counts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."till_counts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.till_counts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.till_counts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."till_deposits" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'till_deposits', 'bsb_audit', 'better_supabase.till_deposits has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'till_deposits', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.till_deposits calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."till_deposits"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.till_deposits is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."till_deposits"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.till_deposits is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.till_deposits write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."till_movements" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'till_movements', 'bsb_audit', 'better_supabase.till_movements has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'till_movements', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.till_movements calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."till_movements"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.till_movements is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."till_movements"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.till_movements is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.till_movements write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."till_sessions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'till_sessions', 'bsb_audit', 'better_supabase.till_sessions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'till_sessions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.till_sessions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."till_sessions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.till_sessions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."till_sessions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.till_sessions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.till_sessions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."tills" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'tills', 'bsb_audit', 'better_supabase.tills has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'tills', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.tills calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."tills"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.tills is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."tills"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.tills is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.tills write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."time_entries" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'time_entries', 'bsb_audit', 'better_supabase.time_entries has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'time_entries', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.time_entries calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."time_entries"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.time_entries is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."time_entries"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.time_entries is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.time_entries write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."time_rates" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'time_rates', 'bsb_audit', 'better_supabase.time_rates has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'time_rates', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.time_rates calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."time_rates"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.time_rates is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."time_rates"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.time_rates is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.time_rates write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."timeline_entries" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'timeline_entries', 'bsb_audit', 'better_supabase.timeline_entries has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'timeline_entries', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.timeline_entries calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."timeline_entries"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.timeline_entries is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."timeline_entries"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.timeline_entries is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.timeline_entries write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."timesheets" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'timesheets', 'bsb_audit', 'better_supabase.timesheets has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'timesheets', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.timesheets calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."timesheets"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.timesheets is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."timesheets"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.timesheets is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.timesheets write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."variant_sizes" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'variant_sizes', 'bsb_audit', 'better_supabase.variant_sizes has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'variant_sizes', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.variant_sizes calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."variant_sizes"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.variant_sizes is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."variant_sizes"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.variant_sizes is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.variant_sizes write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."versions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'versions', 'bsb_audit', 'better_supabase.versions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'versions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.versions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."versions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.versions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."versions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.versions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.versions write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."waitlist_entries" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'waitlist_entries', 'bsb_audit', 'better_supabase.waitlist_entries has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'waitlist_entries', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.waitlist_entries calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."waitlist_entries"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.waitlist_entries is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."waitlist_entries"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.waitlist_entries is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.waitlist_entries write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."webhook_endpoints" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'webhook_endpoints', 'bsb_audit', 'better_supabase.webhook_endpoints has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'webhook_endpoints', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.webhook_endpoints calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."webhook_endpoints"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.webhook_endpoints is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."webhook_endpoints"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.webhook_endpoints is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.webhook_endpoints write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."work_centers" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'work_centers', 'bsb_audit', 'better_supabase.work_centers has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'work_centers', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.work_centers calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."work_centers"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.work_centers is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."work_centers"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.work_centers is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.work_centers write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."work_item_checklist_items" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'work_item_checklist_items', 'bsb_audit', 'better_supabase.work_item_checklist_items has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'work_item_checklist_items', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.work_item_checklist_items calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."work_item_checklist_items"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.work_item_checklist_items is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."work_item_checklist_items"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.work_item_checklist_items is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.work_item_checklist_items write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."work_items" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'work_items', 'bsb_audit', 'better_supabase.work_items has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'work_items', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.work_items calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."work_items"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.work_items is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."work_items"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.work_items is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.work_items write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."work_order_parts" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'work_order_parts', 'bsb_audit', 'better_supabase.work_order_parts has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'work_order_parts', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.work_order_parts calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."work_order_parts"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.work_order_parts is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."work_order_parts"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.work_order_parts is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.work_order_parts write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."work_orders" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'work_orders', 'bsb_audit', 'better_supabase.work_orders has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'work_orders', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.work_orders calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."work_orders"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.work_orders is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."work_orders"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.work_orders is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.work_orders write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."work_projects" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'work_projects', 'bsb_audit', 'better_supabase.work_projects has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'work_projects', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.work_projects calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."work_projects"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.work_projects is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."work_projects"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.work_projects is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.work_projects write entries');
drop table pg_temp.bsb_audit_probe;

create temp table bsb_audit_probe (like "better_supabase"."workflow_definitions" including defaults including identity including generated) on commit drop;
do $$
declare
  col record;
  sets text;
begin
  for col in
    select a.attname from pg_catalog.pg_attribute a
    where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
      and a.attnotnull and a.attidentity = ''
  loop
    execute format('alter table pg_temp.bsb_audit_probe alter column %I drop not null', col.attname);
  end loop;
  perform better_supabase.audit('pg_temp.bsb_audit_probe', ignore => '{}'::text[], redact => '{}'::text[]);
  insert into pg_temp.bsb_audit_probe default values;
  select string_agg(format('%I = %s', a.attname, v.value), ', ') into sets
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_type t on t.oid = a.atttypid
  cross join lateral (
    select case
      when t.typtype = 'e' then quote_literal((select e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = t.oid order by e.enumsortorder limit 1)) || '::' || format_type(t.oid, null)
      when t.typtype <> 'b' then null
      when t.typname = 'uuid' then 'gen_random_uuid()'
      when t.typname in ('json', 'jsonb') then quote_literal('{"probe": true}') || '::' || t.typname
      when t.typname = 'bool' then 'true'
      when t.typname in ('date') then quote_literal('2001-02-03') || '::date'
      when t.typname in ('time', 'timetz') then quote_literal('04:05:06') || '::' || t.typname
      when t.typcategory = 'D' then quote_literal('2001-02-03 04:05:06+00') || '::' || t.typname
      when t.typcategory = 'N' then '1'
      when t.typcategory = 'S' then quote_literal('p')
      when t.typcategory = 'A' then quote_literal('{}') || '::' || format_type(t.oid, null)
    end as value
  ) v
  where a.attrelid = 'pg_temp.bsb_audit_probe'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attidentity = '' and a.attgenerated = '' and v.value is not null;
  if sets is not null then
    execute format('update pg_temp.bsb_audit_probe set %s', sets);
  end if;
  delete from pg_temp.bsb_audit_probe;
end;
$$;
select extensions.has_trigger('better_supabase', 'workflow_definitions', 'bsb_audit', 'better_supabase.workflow_definitions has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'workflow_definitions', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.workflow_definitions calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."workflow_definitions"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.workflow_definitions is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."workflow_definitions"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.workflow_definitions is registered with its redacted columns');
select extensions.results_eq($$select l."op"::text from "better_supabase"."audit_events" l where l."table_name" = (select n.nspname from pg_catalog.pg_namespace n where n.oid = pg_catalog.pg_my_temp_schema()) || '.bsb_audit_probe' order by l."id"$$, $$values ('insert'), ('update'), ('delete')$$, 'inserts, updates and deletes on better_supabase.workflow_definitions write entries');
drop table pg_temp.bsb_audit_probe;

select * from extensions.finish();
rollback;
