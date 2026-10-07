export const REGISTER = `drop function if exists better_supabase.audit(regclass, text[]);
drop function if exists better_supabase.audit(regclass, text[], boolean);
drop function if exists better_supabase.audit(regclass, text[], boolean, text[], text, text, text, text);

-- select better_supabase.audit('public.customers', ignore => '{updated_at}');
-- redact => '{api_key}' masks values but keeps them in changed;
-- event_prefix, category and target_type name the entries (event_prefix.created);
-- tenant_column overrides the module's tenant column for this table, and
-- label_column names the column kept as the entry's target label.
-- replace_trigger => true drops another audit trigger on the table.
create or replace function better_supabase.audit(
  target regclass,
  ignore text[] default '{}',
  replace_trigger boolean default false,
  redact text[] default '{}',
  category text default null,
  event_prefix text default null,
  target_type text default null,
  tenant_column text default null,
  label_column text default null
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  keys text[];
begin
  perform better_supabase.replace_equivalent_triggers(
    target, 'bs_audit', 'audit', replace_trigger
  );
  select array_agg(c.attname::text order by k.ord) into keys
  from pg_catalog.pg_index i
  cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
  join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
  where i.indrelid = audit.target and i.indisprimary;
  delete from better_supabase.audited_tables a where a.target = audit.target;
  execute format('drop trigger if exists bs_audit on %s', target);
  execute format(
    'create trigger bs_audit after insert or update or delete on %s for each row execute function better_supabase.audit_row_change(%L)',
    target,
    jsonb_strip_nulls(jsonb_build_object(
      'ignore', to_jsonb(coalesce(audit.ignore, '{}')),
      'redact', to_jsonb(coalesce(audit.redact, '{}')),
      'key_columns', to_jsonb(keys),
      'category', audit.category,
      'event_prefix', audit.event_prefix,
      'target_type', audit.target_type,
      'tenant_column', audit.tenant_column,
      'label_column', audit.label_column
    ))::text
  );
end;
$$;

create or replace function better_supabase.audit_settings(target regclass)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select convert_from(substring(t.tgargs from 1 for position('\\x00'::bytea in t.tgargs) - 1), 'utf8')::jsonb
     from pg_catalog.pg_trigger t
     where t.tgrelid = audit_settings.target and t.tgname = 'bs_audit' and t.tgnargs > 0),
    (select jsonb_strip_nulls(jsonb_build_object(
       'ignore', to_jsonb(a.ignore), 'redact', to_jsonb(a.redact), 'key_columns', to_jsonb(a.key_columns),
       'category', a.category, 'event_prefix', a.event_prefix, 'target_type', a.target_type,
       'tenant_column', a.tenant_column, 'label_column', a.label_column))
     from better_supabase.audited_tables a where a.target = audit_settings.target)
  )
$$;

create or replace function better_supabase.unaudit(target regclass)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bs_audit on %s', target);
  delete from better_supabase.audited_tables a where a.target = unaudit.target;
end;
$$;

-- The audit() calls for every table in schema_name with tenant_column,
-- except tables whose name matches an exempt pattern (like 'audit_%').
-- Paste them into a schema file: static calls keep their place in a
-- pg-delta diff, where a loop over the catalog runs before the tables exist.
--   select better_supabase.audit_schema_calls('public', 'tenant_id', '{audit_%}');
create or replace function better_supabase.audit_schema_calls(
  schema_name text,
  tenant_column text,
  exempt text[] default '{}'
)
returns setof text
language sql
stable
set search_path = ''
as $$
  select format('select better_supabase.audit(%L);', format('%I.%I', n.nspname, c.relname))
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = schema_name
    and c.relkind in ('r', 'p')
    and not c.relispartition
    and exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = c.oid and a.attname = tenant_column and a.attnum > 0 and not a.attisdropped
    )
    and not exists (select 1 from unnest(exempt) e where c.relname like e)
  order by c.relname
$$;

-- Registers those tables now, for a migration or a one-off script; tables
-- already registered keep their own settings. Returns how many it added.
create or replace function better_supabase.audit_schema(
  schema_name text,
  tenant_column text,
  exempt text[] default '{}'
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  registered integer := 0;
  target regclass;
begin
  for target in
    select format('%I.%I', n.nspname, c.relname)::regclass
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = schema_name
      and c.relkind in ('r', 'p')
      and not c.relispartition
      and exists (
        select 1 from pg_catalog.pg_attribute a
        where a.attrelid = c.oid and a.attname = audit_schema.tenant_column and a.attnum > 0 and not a.attisdropped
      )
      and not exists (select 1 from unnest(exempt) e where c.relname like e)
      and not exists (
        select 1 from pg_catalog.pg_trigger t where t.tgrelid = c.oid and t.tgname = 'bs_audit'
      )
    order by c.relname
  loop
    perform better_supabase.audit(target);
    registered := registered + 1;
  end loop;
  return registered;
end;
$$;

revoke execute on function better_supabase.audit(regclass, text[], boolean, text[], text, text, text, text, text) from public, anon, authenticated;
revoke execute on function better_supabase.unaudit(regclass) from public, anon, authenticated;
revoke execute on function better_supabase.audit_settings(regclass) from public, anon, authenticated;
revoke execute on function better_supabase.audit_schema_calls(text, text, text[]) from public, anon, authenticated;
revoke execute on function better_supabase.audit_schema(text, text, text[]) from public, anon, authenticated;`;
