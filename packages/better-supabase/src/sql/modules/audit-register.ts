export const REGISTER = `drop function if exists better_supabase.audit(regclass, text[]);
drop function if exists better_supabase.audit(regclass, text[], boolean);
drop function if exists better_supabase.audit(regclass, text[], boolean, text[], text, text, text, text);
drop function if exists better_supabase.audit(regclass, text[], boolean, text[], text, text, text, text, text);

-- select better_supabase.audit('public.customers', ignore => '{updated_at}');
-- redact => '{api_key}' masks values but keeps them in changed;
-- event_prefix, category and target_type name the entries (event_prefix.created);
-- tenant_column overrides the module's tenant column for this table, and
-- label_column names the column kept as the entry's target label.
-- tenant_path resolves the tenant of a child row that has no tenant column
-- through foreign keys: 'group_id -> directory_groups.organization_id' reads
-- organization_id from the directory_groups row that group_id references,
-- and further '-> table.column' hops continue from there. tenant_function
-- names a function (jsonb) that returns the tenant of a row. The trigger
-- tries the row's tenant column, then the path, then the function.
-- ignore also keeps the update trigger from firing when only ignored columns
-- change, so writes such as last_run_at cost nothing.
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
  label_column text default null,
  tenant_path text default null,
  tenant_function regprocedure default null
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  keys text[];
  path_steps jsonb := '[]';
  path_column text;
  parts text[];
  cur_rel regclass := target;
  cur_col text;
  ref_rel regclass;
  ref_col text;
  segment text;
  seg_table text;
  seg_read text;
  base_settings jsonb;
begin
  if audit.tenant_path is not null then
    parts := regexp_split_to_array(btrim(audit.tenant_path), '\\s*->\\s*');
    if coalesce(array_length(parts, 1), 0) < 2 then
      raise exception 'tenant_path % needs a column and at least one table.column hop', audit.tenant_path;
    end if;
    path_column := parts[1];
    cur_col := path_column;
    for i in 2..array_length(parts, 1) loop
      segment := parts[i];
      seg_read := substring(segment from '[^.]+$');
      seg_table := substring(segment from '^(.*)\\.[^.]+$');
      if seg_read is null or seg_table is null then
        raise exception 'tenant_path hop % must be table.column', segment;
      end if;
      select con.confrelid::regclass, a.attname::text into ref_rel, ref_col
      from pg_catalog.pg_constraint con
      join pg_catalog.pg_attribute a on a.attrelid = con.confrelid and a.attnum = con.confkey[1]
      where con.contype = 'f' and con.conrelid = cur_rel and array_length(con.conkey, 1) = 1
        and con.conkey[1] = (
          select c.attnum from pg_catalog.pg_attribute c
          where c.attrelid = cur_rel and c.attname = cur_col and not c.attisdropped
        );
      if ref_rel is null then
        raise exception 'tenant_path: % has no foreign key on column %', cur_rel, cur_col;
      end if;
      if pg_catalog.to_regclass(case when position('.' in seg_table) > 0 then seg_table else (select n.nspname from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace where c.oid = audit.target) || '.' || seg_table end) is distinct from ref_rel then
        raise exception 'tenant_path: % does not reference %', cur_col, seg_table;
      end if;
      path_steps := path_steps || jsonb_build_array(jsonb_build_object('table', ref_rel::text, 'ref', ref_col, 'read', seg_read));
      cur_rel := ref_rel;
      cur_col := seg_read;
    end loop;
  end if;
  perform better_supabase.replace_equivalent_triggers(
    target, 'bsb_audit', 'audit', replace_trigger
  );
  select array_agg(c.attname::text order by k.ord) into keys
  from pg_catalog.pg_index i
  cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
  join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
  where i.indrelid = audit.target and i.indisprimary;
  delete from better_supabase.audited_tables a where a.target = audit.target;
  base_settings := jsonb_strip_nulls(jsonb_build_object(
    'ignore', to_jsonb(coalesce(audit.ignore, '{}')),
    'redact', to_jsonb(coalesce(audit.redact, '{}')),
    'key_columns', to_jsonb(keys),
    'category', audit.category,
    'event_prefix', audit.event_prefix,
    'target_type', audit.target_type,
    'tenant_column', audit.tenant_column,
    'label_column', audit.label_column,
    'tenant_path', case when audit.tenant_path is not null then jsonb_build_object('column', path_column, 'steps', path_steps) end,
    'tenant_function', audit.tenant_function::text
  ));
  execute format('drop trigger if exists bsb_audit on %s', target);
  execute format('drop trigger if exists bsb_audit_update on %s', target);
  if cardinality(coalesce(audit.ignore, '{}')) > 0 then
    execute format(
      'create trigger bsb_audit after insert or delete on %s for each row execute function better_supabase.audit_row_change(%L)',
      target, base_settings::text
    );
    execute format(
      'create trigger bsb_audit_update after update on %s for each row when ((to_jsonb(old) - %L::text[]) is distinct from (to_jsonb(new) - %L::text[])) execute function better_supabase.audit_row_change(%L)',
      target, audit.ignore, audit.ignore, base_settings::text
    );
  else
    execute format(
      'create trigger bsb_audit after insert or update or delete on %s for each row execute function better_supabase.audit_row_change(%L)',
      target, base_settings::text
    );
  end if;
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
     where t.tgrelid = audit_settings.target and t.tgname = 'bsb_audit' and t.tgnargs > 0),
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
  execute format('drop trigger if exists bsb_audit on %s', target);
  execute format('drop trigger if exists bsb_audit_update on %s', target);
  delete from better_supabase.audited_tables a where a.target = unaudit.target;
end;
$$;

create or replace function better_supabase.unaudit(target text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  relation regclass := pg_catalog.to_regclass(unaudit.target);
begin
  if relation is not null then
    perform better_supabase.unaudit(relation);
  end if;
  delete from better_supabase.audited_tables a
  where not exists (select 1 from pg_catalog.pg_class c where c.oid = a.target::oid);
end;
$$;

create or replace function better_supabase.audit_forget_dropped()
returns event_trigger
language plpgsql
set search_path = ''
as $$
begin
  delete from better_supabase.audited_tables a
  where a.target::oid in (
    select d.objid from pg_catalog.pg_event_trigger_dropped_objects() d
    where d.object_type = 'table'
  );
end;
$$;

drop event trigger if exists bsb_audit_forget_dropped;
create event trigger bsb_audit_forget_dropped on sql_drop
  when tag in ('DROP TABLE', 'DROP SCHEMA')
  execute function better_supabase.audit_forget_dropped();

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
        select 1 from pg_catalog.pg_trigger t where t.tgrelid = c.oid and t.tgname = 'bsb_audit'
      )
    order by c.relname
  loop
    perform better_supabase.audit(target);
    registered := registered + 1;
  end loop;
  return registered;
end;
$$;

revoke execute on function better_supabase.audit(regclass, text[], boolean, text[], text, text, text, text, text, text, regprocedure) from public, anon, authenticated;
revoke execute on function better_supabase.unaudit(regclass) from public, anon, authenticated;
revoke execute on function better_supabase.unaudit(text) from public, anon, authenticated;
revoke execute on function better_supabase.audit_forget_dropped() from public, anon, authenticated;
revoke execute on function better_supabase.audit_settings(regclass) from public, anon, authenticated;
revoke execute on function better_supabase.audit_schema_calls(text, text, text[]) from public, anon, authenticated;
revoke execute on function better_supabase.audit_schema(text, text, text[]) from public, anon, authenticated;`;
