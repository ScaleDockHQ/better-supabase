-- better-supabase module: audit
-- @bs-module audit@9 adopt
-- Records inserts, updates and deletes with the actor and changed columns for tables you register, plus semantic events through audit_event(), with redaction, an append-only guard, a tenant read policy and per-tenant retention as options.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists better_supabase.audited_tables (
  target regclass primary key,
  ignore text[] not null default '{}'
);
-- The primary key columns, read when the table is registered; composite keys are joined with ','.
alter table better_supabase.audited_tables add column if not exists key_columns text[] not null default '{id}';
-- Per-table event naming and redaction.
alter table better_supabase.audited_tables add column if not exists redact text[] not null default '{}';
alter table better_supabase.audited_tables add column if not exists category text;
alter table better_supabase.audited_tables add column if not exists event_prefix text;
alter table better_supabase.audited_tables add column if not exists target_type text;
alter table better_supabase.audited_tables add column if not exists tenant_column text;
alter table better_supabase.audited_tables add column if not exists label_column text;
alter table better_supabase.audited_tables enable row level security;
revoke all on better_supabase.audited_tables from anon, authenticated;

-- The user a service caller acts for, from the x-bsb-actor header. Null for
-- every other caller, so the header cannot be spoofed with a user's token.
-- Only service_role may call it; the security definer functions and triggers
-- that record an actor call it as their owner.
create or replace function better_supabase.acting_member()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  header text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    return null;
  end if;
  header := nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-bsb-actor';
  return case when header ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then header::uuid end;
exception when others then
  return null;
end;
$$;
revoke execute on function better_supabase.acting_member() from public, anon, authenticated;
grant execute on function better_supabase.acting_member() to service_role;

-- The request headers, or null outside a Data API request.
create or replace function better_supabase.request_headers()
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  return nullif(current_setting('request.headers', true), '')::jsonb;
exception when others then
  return null;
end;
$$;

-- One request header, or null outside a Data API request.
create or replace function better_supabase.request_header(name text)
returns text
language plpgsql
stable
set search_path = ''
as $$
begin
  return nullif(current_setting('request.headers', true), '')::jsonb ->> request_header.name;
exception when others then
  return null;
end;
$$;

create or replace function better_supabase.request_id_or_null(value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when value ~ '^[A-Za-z0-9._:;,@/+=-]{1,128}$' then value end;
$$;

-- The client address the API gateway appended to x-forwarded-for (the
-- right-most hop; clients can forge the ones before it), or null.
create or replace function better_supabase.request_ip()
returns inet
language plpgsql
stable
set search_path = ''
as $$
begin
  return nullif(trim(reverse(split_part(reverse(current_setting('request.headers', true)::json ->> 'x-forwarded-for'), ',', 1))), '')::inet;
exception when others then
  return null;
end;
$$;

create or replace function better_supabase.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry record;
  settings jsonb;
  entry_id "centrakit"."audit_logs"."id"%type;
  old_row jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  new_row jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  row_data jsonb := coalesce(new_row, old_row);
  changed_columns text[];
  changed_values jsonb;
  row_tenant uuid;
  v_jwt jsonb := auth.jwt();
  v_headers jsonb := better_supabase.request_headers();
  path_value text;
  path_step jsonb;
begin
  if tg_nargs > 0 then
    settings := tg_argv[0]::jsonb;
    select array(select jsonb_array_elements_text(coalesce(settings -> 'ignore', '[]'))) as ignore,
      coalesce(
        nullif(array(select jsonb_array_elements_text(coalesce(settings -> 'key_columns', '[]'))), '{}'),
        (select array_agg(c.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
         where i.indrelid = tg_relid and i.indisprimary),
        '{id}'
      ) as key_columns,
      array(select jsonb_array_elements_text(coalesce(settings -> 'redact', '[]'))) as redact,
      settings ->> 'category' as category, settings ->> 'event_prefix' as event_prefix,
      settings ->> 'target_type' as target_type, settings ->> 'tenant_column' as tenant_column,
      settings ->> 'label_column' as label_column,
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function
    into entry;
  else
    select coalesce(a.ignore, '{}') as ignore, coalesce(a.key_columns, '{id}') as key_columns,
      coalesce(a.redact, '{}') as redact, a.category, a.event_prefix, a.target_type, a.tenant_column,
      a.label_column, null::jsonb as tenant_path, null::text as tenant_function
    into entry
    from (select 1) one
    left join better_supabase.audited_tables a on a.target = tg_relid::regclass;
  end if;
  row_tenant := case when row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end;
  -- A child row without a tenant column: follow the foreign-key path
  -- registered through tenant_path, then the tenant function.
  if row_tenant is null and entry.tenant_path is not null then
    path_value := row_data ->> (entry.tenant_path ->> 'column');
    for path_step in select * from jsonb_array_elements(entry.tenant_path -> 'steps') loop
      exit when path_value is null;
      execute format('select %I::text from %s where %I::text = $1 limit 1',
        path_step ->> 'read', path_step ->> 'table', path_step ->> 'ref')
        into path_value using path_value;
    end loop;
    row_tenant := case when path_value ~* '^[0-9a-f-]{36}$' then (path_value)::uuid end;
  end if;
  if row_tenant is null and entry.tenant_function is not null then
    execute format('select %s($1)::text', (entry.tenant_function::regprocedure)::oid::regproc) into path_value using row_data;
    row_tenant := case when path_value ~* '^[0-9a-f-]{36}$' then (path_value)::uuid end;
  end if;
  old_row := old_row - entry.ignore;
  new_row := new_row - entry.ignore;
  if tg_op = 'UPDATE' then
    select array_agg(key order by key) into changed_columns
    from jsonb_each(new_row) n
    where n.value is distinct from old_row -> n.key;
    if changed_columns is null then
      return null;
    end if;
  end if;
  -- Redacted columns stay in changed, with their values masked.
  old_row := old_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where old_row ? k), '{}');
  new_row := new_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where new_row ? k), '{}');
  -- One change per column, values cut at 1000 characters, for revealing a
  -- single change without the whole rows.
  select jsonb_object_agg(k, jsonb_build_object(
    'old', case when length((old_row -> k)::text) > 1000 then to_jsonb(left((old_row -> k)::text, 1000)) else old_row -> k end,
    'new', case when length((new_row -> k)::text) > 1000 then to_jsonb(left((new_row -> k)::text, 1000)) else new_row -> k end
  ))
  into changed_values
  from unnest(coalesce(changed_columns, array(select jsonb_object_keys(coalesce(new_row, old_row))))) k;
  insert into "centrakit"."audit_logs" ("target_id", "actor_id", "organization_id", "event_type", "category", "outcome", "source", "target_type")
  values (
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    coalesce(auth.uid(), better_supabase.acting_member()),
    row_tenant,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
    case (coalesce(entry.category, 'data')) when 'membership' then 'users' when 'access' then 'permissions' when 'configuration' then 'settings' when 'integration' then 'integrations' when 'ai' then 'system' else (coalesce(entry.category, 'data')) end,
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name)
  )
  returning "id" into entry_id;
  insert into "centrakit"."audit_log_restricted_details" ("event_id", "ip_address", "user_agent", "restricted_metadata")
  values (entry_id, better_supabase.request_ip(), (v_headers ->> 'user-agent'), '{}'::jsonb);
  return null;
end;
$$;
revoke execute on function better_supabase.audit_row_change() from public, anon, authenticated;

create or replace function better_supabase.replace_equivalent_triggers(
  target regclass,
  module_trigger text,
  pattern text,
  replace_trigger boolean
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  found record;
begin
  for found in
    select t.tgname as name, p.proname as fn
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = replace_equivalent_triggers.target
      and not t.tgisinternal
      and t.tgname <> replace_equivalent_triggers.module_trigger
      and p.proname ~* replace_equivalent_triggers.pattern
  loop
    if replace_trigger then
      execute format('drop trigger %I on %s', found.name, target);
    else
      raise warning '% already has trigger % (%), which does what % does. Pass replace_trigger => true to drop it.',
        target, found.name, found.fn, module_trigger;
    end if;
  end loop;
end;
$$;
revoke execute on function better_supabase.replace_equivalent_triggers(regclass, text, text, boolean) from public, anon, authenticated;

drop function if exists better_supabase.audit(regclass, text[]);
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
    parts := regexp_split_to_array(btrim(audit.tenant_path), '\s*->\s*');
    if coalesce(array_length(parts, 1), 0) < 2 then
      raise exception 'tenant_path % needs a column and at least one table.column hop', audit.tenant_path;
    end if;
    path_column := parts[1];
    cur_col := path_column;
    for i in 2..array_length(parts, 1) loop
      segment := parts[i];
      seg_read := substring(segment from '[^.]+$');
      seg_table := substring(segment from '^(.*)\.[^.]+$');
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
    (select convert_from(substring(t.tgargs from 1 for position('\x00'::bytea in t.tgargs) - 1), 'utf8')::jsonb
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
revoke execute on function better_supabase.audit_schema(text, text, text[]) from public, anon, authenticated;

-- Records a semantic app event (invoice.sent, member.invited) next to the
-- row changes. A repeated idempotency_key returns the first entry's id.
-- actor_id, actor_kind, actor_label, ip, user_agent, session_id, request_id
-- and scope are honoured for the service role and direct admin connections,
-- which never get the request's own address, user agent or session; everyone
-- else gets auth.uid() and the request's own values. support_session,
-- impersonated_by and impersonation_reason fill the impersonation columns;
-- other callers may only name themselves as impersonated_by, from a token
-- without an act claim (an admin starting or ending their own support
-- session), and otherwise get the act claim's values. restricted goes to the
-- restricted table, with no row when every restricted value is empty; without
-- that table, passing it fails instead of dropping the details.
drop function if exists better_supabase.audit_event(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid);
drop function if exists better_supabase.audit_event(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text);
drop function if exists better_supabase.audit_event(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text);
drop function if exists better_supabase.audit_event(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text);
drop function if exists better_supabase.audit_event(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text);
create or replace function better_supabase.audit_event(
  event_type text,
  category text default null,
  outcome text default 'success',
  source text default null,
  target_type text default null,
  record_id text default null,
  tenant uuid default null,
  metadata jsonb default '{}',
  idempotency_key text default null,
  restricted jsonb default null,
  actor_id uuid default null,
  summary text default null,
  target_label text default null,
  correlation_id text default null,
  actor_kind text default null,
  actor_label text default null,
  ip inet default null,
  user_agent text default null,
  session_id text default null,
  request_id text default null,
  scope text default null,
  support_session uuid default null,
  impersonated_by uuid default null,
  impersonation_reason text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing text;
  entry_id "centrakit"."audit_logs"."id"%type;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    actor_id := auth.uid();
    actor_kind := null;
    actor_label := null;
    ip := better_supabase.request_ip();
    user_agent := better_supabase.request_header('user-agent');
    session_id := auth.jwt() ->> 'session_id';
    request_id := null;
    scope := null;
    if (select auth.jwt()) -> 'act' is not null or impersonated_by is distinct from auth.uid() then
      support_session := null;
      impersonated_by := null;
      impersonation_reason := null;
    end if;
  elsif actor_id is null then
    actor_id := coalesce(auth.uid(), better_supabase.acting_member());
  end if;
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l."id"::text into existing
    from "centrakit"."audit_logs" l
    where l."idempotency_key" = audit_event.idempotency_key
      and l."organization_id" is not distinct from audit_event.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "centrakit"."audit_logs" ("target_id", "actor_id", "organization_id", "event_type", "category", "outcome", "source", "target_type", "safe_metadata", "idempotency_key")
  values (
    record_id,
    actor_id,
    tenant,
    event_type,
    case (coalesce(category, 'data')) when 'membership' then 'users' when 'access' then 'permissions' when 'configuration' then 'settings' when 'integration' then 'integrations' when 'ai' then 'system' else (coalesce(category, 'data')) end,
    coalesce(outcome, 'success'),
    coalesce(source, 'saas'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key
  )
  returning "id" into entry_id;
  if coalesce(restricted, '{}') <> '{}' or ip is not null or nullif(user_agent, '') is not null or nullif(session_id, '') is not null then
    insert into "centrakit"."audit_log_restricted_details" ("event_id", "ip_address", "user_agent", "restricted_metadata")
    values (entry_id, ip, user_agent, coalesce(restricted, '{}'));
  end if;
  return entry_id::text;
end;
$$;
revoke execute on function better_supabase.audit_event(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.audit_event(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text) to "service_role";

-- audit_event for a batch of events in one call (the outbox sink): each
-- element takes audit_event's argument names as keys, keeps its checks and
-- returns {"id"} or {"error"} in order.
create or replace function better_supabase.audit_event_many(events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  batch_event jsonb;
  results jsonb := '[]';
  batch_result text;
  failed_state text;
  failed_message text;
  failed_hint text;
begin
  if pg_catalog.jsonb_typeof(events) is distinct from 'array' then
    raise exception 'audit_event_many takes a jsonb array of events'
      using errcode = '22023', hint = 'AUDIT_BATCH_NOT_ARRAY';
  end if;
  if pg_catalog.jsonb_array_length(events) > 1000 then
    raise exception 'audit_event_many got % events, more than 1000', pg_catalog.jsonb_array_length(events)
      using errcode = '22023', hint = 'AUDIT_BATCH_TOO_LARGE';
  end if;
  for batch_event in select e from pg_catalog.jsonb_array_elements(events) e loop
    begin
      batch_result := better_supabase.audit_event(
        event_type => batch_event ->> 'event_type',
        category => batch_event ->> 'category',
        outcome => coalesce(batch_event ->> 'outcome', 'success'),
        source => batch_event ->> 'source',
        target_type => batch_event ->> 'target_type',
        record_id => batch_event ->> 'record_id',
        tenant => (batch_event ->> 'tenant')::uuid,
        metadata => coalesce(nullif(batch_event -> 'metadata', 'null'::jsonb), '{}'),
        idempotency_key => batch_event ->> 'idempotency_key',
        restricted => nullif(batch_event -> 'restricted', 'null'::jsonb),
        actor_id => (batch_event ->> 'actor_id')::uuid,
        summary => batch_event ->> 'summary',
        target_label => batch_event ->> 'target_label',
        correlation_id => batch_event ->> 'correlation_id',
        actor_kind => batch_event ->> 'actor_kind',
        actor_label => batch_event ->> 'actor_label',
        ip => (batch_event ->> 'ip')::inet,
        user_agent => batch_event ->> 'user_agent',
        session_id => batch_event ->> 'session_id',
        request_id => batch_event ->> 'request_id',
        scope => batch_event ->> 'scope',
        support_session => (batch_event ->> 'support_session')::uuid,
        impersonated_by => (batch_event ->> 'impersonated_by')::uuid,
        impersonation_reason => batch_event ->> 'impersonation_reason'
      );
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('id', batch_result));
    exception when others then
      get stacked diagnostics
        failed_state = returned_sqlstate,
        failed_message = message_text,
        failed_hint = pg_exception_hint;
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object('code', failed_state, 'message', failed_message, 'hint', nullif(failed_hint, ''))
      ));
    end;
  end loop;
  return results;
end;
$$;
revoke execute on function better_supabase.audit_event_many(jsonb) from public, anon, authenticated;
grant execute on function better_supabase.audit_event_many(jsonb) to "service_role";

-- audit_event for the app's own security definer functions: it honours
-- actor_id, actor_kind, actor_label, scope and the request details from any
-- caller, so only the owner, the service role and
-- blocks.audit.options.trustedRoles may execute it. A function owned by
-- postgres calls it on behalf of a client with the real actor context.
drop function if exists better_supabase.audit_event_trusted(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text);
drop function if exists better_supabase.audit_event_trusted(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text);
create or replace function better_supabase.audit_event_trusted(
  event_type text,
  category text default null,
  outcome text default 'success',
  source text default null,
  target_type text default null,
  record_id text default null,
  tenant uuid default null,
  metadata jsonb default '{}',
  idempotency_key text default null,
  restricted jsonb default null,
  actor_id uuid default null,
  summary text default null,
  target_label text default null,
  correlation_id text default null,
  actor_kind text default null,
  actor_label text default null,
  ip inet default null,
  user_agent text default null,
  session_id text default null,
  request_id text default null,
  scope text default null,
  support_session uuid default null,
  impersonated_by uuid default null,
  impersonation_reason text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing text;
  entry_id "centrakit"."audit_logs"."id"%type;
begin
  actor_id := coalesce(actor_id, auth.uid());
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l."id"::text into existing
    from "centrakit"."audit_logs" l
    where l."idempotency_key" = audit_event_trusted.idempotency_key
      and l."organization_id" is not distinct from audit_event_trusted.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "centrakit"."audit_logs" ("target_id", "actor_id", "organization_id", "event_type", "category", "outcome", "source", "target_type", "safe_metadata", "idempotency_key")
  values (
    record_id,
    actor_id,
    tenant,
    event_type,
    case (coalesce(category, 'data')) when 'membership' then 'users' when 'access' then 'permissions' when 'configuration' then 'settings' when 'integration' then 'integrations' when 'ai' then 'system' else (coalesce(category, 'data')) end,
    coalesce(outcome, 'success'),
    coalesce(source, 'saas'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key
  )
  returning "id" into entry_id;
  if coalesce(restricted, '{}') <> '{}' or ip is not null or nullif(user_agent, '') is not null or nullif(session_id, '') is not null then
    insert into "centrakit"."audit_log_restricted_details" ("event_id", "ip_address", "user_agent", "restricted_metadata")
    values (entry_id, ip, user_agent, coalesce(restricted, '{}'));
  end if;
  return entry_id::text;
end;
$$;
revoke execute on function better_supabase.audit_event_trusted(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.audit_event_trusted(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text, uuid, uuid, text) to "service_role";

drop trigger if exists "bsb_audit_append_only" on "centrakit"."audit_logs";
drop trigger if exists "bsb_audit_no_truncate" on "centrakit"."audit_logs";

-- Members read their tenant's entries with the audit.view permission;
-- platform staff read every entry. PL/pgSQL resolves tenant_ids_with and
-- is_platform when it runs, so this file installs before the access module's.
create or replace function "better_supabase"."audit_read_tenants"()
returns setof uuid
language plpgsql
stable
set search_path = ''
as $$
begin
  return query select t::uuid from better_supabase.tenant_ids_with('audit.view') t;
end;
$$;
create or replace function "better_supabase"."audit_reads_all"()
returns boolean
language plpgsql
stable
set search_path = ''
as $$
begin
  return (select coalesce(better_supabase.is_platform('platform.users.manage'), false));
end;
$$;
revoke execute on function "better_supabase"."audit_read_tenants"() from public, anon;
revoke execute on function "better_supabase"."audit_reads_all"() from public, anon;
grant execute on function "better_supabase"."audit_read_tenants"() to authenticated, service_role;
grant execute on function "better_supabase"."audit_reads_all"() to authenticated, service_role;
drop policy if exists bsb_audit_read on "centrakit"."audit_logs";
create policy bsb_audit_read on "centrakit"."audit_logs" for select to authenticated
  using (
    "organization_id" in (select "better_supabase"."audit_read_tenants"())
    or (select "better_supabase"."audit_reads_all"())
  );
grant select on "centrakit"."audit_logs" to authenticated;

-- Deletes up to batch entries older than older_than and returns how many.
-- With an audit_retention(tenant) function, each tenant keeps its own
-- interval (a plan's days, say); null falls back to the data-lifecycle
-- retention policy, then older_than. Entries under a legal hold stay. With
-- for_tenant, only entries of tenant (null: entries without one).
-- Nightly with pg_cron or the jobs drain route:
--   select better_supabase.purge_audit_log();
drop function if exists better_supabase.purge_audit_log(interval, integer);
create or replace function better_supabase.purge_audit_log(
  older_than interval default '1 year',
  batch integer default 10000,
  tenant uuid default null,
  for_tenant boolean default false
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  purged integer := 0;
  gone integer;
  v_tenant uuid;
  v_older interval;
begin
  perform set_config('better_supabase.audit_purge', 'on', true);
  if not for_tenant and to_regprocedure('"public"."audit_retention"(uuid)') is not null then
    -- One delete per tenant with that tenant's interval as a constant, so
    -- each runs on the (tenant, occurred_at) index. The tenants come from a
    -- skip scan of that index, not a scan of the log.
    for v_tenant in
      with recursive t (v) as (
        (select l."organization_id" from "centrakit"."audit_logs" l where l."organization_id" is not null order by l."organization_id" limit 1)
        union all
        select (select l."organization_id" from "centrakit"."audit_logs" l where l."organization_id" > t.v order by l."organization_id" limit 1)
        from t where t.v is not null
      )
      select t.v from t where t.v is not null
    loop
      exit when purged >= batch;
      continue when "better_supabase"."is_held"('audit', (v_tenant)::text);
      -- Not a literal name, so plpgsql_check passes without the hook.
      execute format('select %s($1)', to_regprocedure('"public"."audit_retention"(uuid)')::oid::regproc)
        into v_older using v_tenant;
      v_older := coalesce(v_older, coalesce("better_supabase"."retention_for"('audit', (v_tenant)::text), older_than));
      with deleted as (
        delete from "centrakit"."audit_logs"
        where "id" in (
          select l."id" from "centrakit"."audit_logs" l
          where l."organization_id" = v_tenant and l."occurred_at" < now() - v_older
          order by l."occurred_at"
          limit batch - purged
        )
        returning 1
      )
      select count(*)::integer into gone from deleted;
      purged := purged + gone;
    end loop;
    if purged < batch then
      with deleted as (
        delete from "centrakit"."audit_logs"
        where "id" in (
          select l."id" from "centrakit"."audit_logs" l
          where l."organization_id" is null and (l."occurred_at" < now() - least(older_than, "better_supabase"."retention_floor"('audit'))
      and l."occurred_at" < now() - coalesce("better_supabase"."retention_for"('audit', (null)::text), older_than)
      and not "better_supabase"."is_held"('audit', (null)::text))
          order by l."occurred_at"
          limit batch - purged
        )
        returning 1
      )
      select count(*)::integer into gone from deleted;
      purged := purged + gone;
    end if;
  else
    with deleted as (
      delete from "centrakit"."audit_logs"
      where "id" in (
        select l."id" from "centrakit"."audit_logs" l
        where (l."occurred_at" < now() - least(older_than, "better_supabase"."retention_floor"('audit'))
      and l."occurred_at" < now() - coalesce("better_supabase"."retention_for"('audit', (l."organization_id")::text), older_than)
      and not "better_supabase"."is_held"('audit', (l."organization_id")::text))
          and (not for_tenant or l."organization_id" is not distinct from purge_audit_log.tenant)
        order by l."occurred_at"
        limit greatest(batch - purged, 0)
      )
      returning 1
    )
    select purged + count(*)::integer into purged from deleted;
  end if;
  perform set_config('better_supabase.audit_purge', 'off', true);
  return purged;
end;
$$;
revoke execute on function better_supabase.purge_audit_log(interval, integer, uuid, boolean) from public, anon, authenticated;
grant execute on function better_supabase.purge_audit_log(interval, integer, uuid, boolean) to service_role;

-- Tenants with entries older than older_than, for a retention callback in TypeScript.
create or replace function better_supabase.audit_events_tenants(older_than interval default '1 day')
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select distinct l."organization_id" from "centrakit"."audit_logs" l
  where l."occurred_at" < now() - older_than
$$;
revoke execute on function better_supabase.audit_events_tenants(interval) from public, anon, authenticated;
grant execute on function better_supabase.audit_events_tenants(interval) to service_role;

-- A page of the entries the caller can read, newest first unless ascending:
-- the read policy decides (security invoker). Each filter takes several
-- values; search matches the event type, summary, labels, record and table.
-- Page with the last entry's occurred_at and id as cursor_at and cursor_id,
-- or open page N with skip (an offset) and count_audit_events for the total.
-- skip is ignored with a cursor, so keyset pages never scan skipped rows.
drop function if exists "better_supabase"."list_audit_events"(uuid, text, uuid, text, text, timestamptz, timestamptz, timestamptz, text, integer);
drop function if exists "better_supabase"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamptz, timestamptz, timestamptz, text, integer, boolean);
create or replace function "better_supabase"."list_audit_events"(
  for_tenants uuid[] default null,
  for_event_types text[] default null,
  for_actors uuid[] default null,
  for_target_types text[] default null,
  for_records text[] default null,
  for_categories text[] default null,
  for_outcomes text[] default null,
  search text default null,
  for_sources text[] default null,
  for_actor_kinds text[] default null,
  for_correlation_ids text[] default null,
  since timestamptz default null,
  until timestamptz default null,
  cursor_at timestamptz default null,
  cursor_id text default null,
  max_items integer default 50,
  ascending boolean default false,
  skip integer default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_where text := 'true';
  v_order text := case when ascending then 'asc' else 'desc' end;
  v_skip text := '';
  result jsonb;
begin
  if cardinality(for_tenants) > 0 then
    v_where := v_where || $q$ and l."organization_id" = any ($1)$q$;
  end if;
  if cardinality(for_event_types) > 0 then
    v_where := v_where || $q$ and l."event_type" = any ($2)$q$;
  end if;
  if cardinality(for_actors) > 0 then
    v_where := v_where || $q$ and l."actor_id" = any ($3)$q$;
  end if;
  if cardinality(for_target_types) > 0 then
    v_where := v_where || $q$ and l."target_type" = any ($4)$q$;
  end if;
  if cardinality(for_records) > 0 then
    v_where := v_where || $q$ and l."target_id" = any ($5)$q$;
  end if;
  if cardinality(for_categories) > 0 then
    v_where := v_where || $q$ and case l."category" when 'users' then 'membership' when 'permissions' then 'access' when 'settings' then 'configuration' when 'integrations' then 'integration' when 'system' then 'ai' else l."category" end = any ($6)$q$;
  end if;
  if cardinality(for_outcomes) > 0 then
    v_where := v_where || $q$ and l."outcome" = any ($7)$q$;
  end if;
  if cardinality(for_sources) > 0 then
    v_where := v_where || $q$ and l."source" = any ($9)$q$;
  end if;
  if search <> '' then
    v_where := v_where || $q$ and concat_ws(' ', l."event_type", l."target_id") ilike '%' || replace(replace(replace($8, '\', '\\'), '%', '\%'), '_', '\_') || '%'$q$;
  end if;
  if since is not null then
    v_where := v_where || $q$ and l."occurred_at" >= $12$q$;
  end if;
  if until is not null then
    v_where := v_where || $q$ and l."occurred_at" < $13$q$;
  end if;
  if cursor_at is not null then
    v_where := v_where || case when ascending
      then $q$ and (l."occurred_at", l."id"::text) > ($14, $15)$q$
      else $q$ and (l."occurred_at", l."id"::text) < ($14, $15)$q$
    end;
  elsif coalesce(skip, 0) > 0 then
    v_skip := ' offset $17';
  end if;
  -- Only the filters passed reach the query, so the planner sees no
  -- "is null or" branches and can use the (tenant, occurred_at) index.
  execute $q$select coalesce(jsonb_agg(x.entry order by x.occurred_at $q$ || v_order || $q$, x.id $q$ || v_order || $q$), '[]')
  from (
    select jsonb_build_object('id', l."id", 'record', l."target_id", 'actorId', l."actor_id", 'tenant', l."organization_id", 'occurredAt', l."occurred_at", 'eventType', l."event_type", 'category', case l."category" when 'users' then 'membership' when 'permissions' then 'access' when 'settings' then 'configuration' when 'integrations' then 'integration' when 'system' then 'ai' else l."category" end, 'outcome', l."outcome", 'source', l."source", 'targetType', l."target_type", 'metadata', l."safe_metadata") as entry, l."occurred_at" as occurred_at, l."id"::text as id
    from "centrakit"."audit_logs" l
    where $q$ || v_where || $q$
    order by l."occurred_at" $q$ || v_order || $q$, l."id"::text $q$ || v_order || $q$
    limit $16$q$ || v_skip || $q$
  ) x$q$
  into result
  using for_tenants, for_event_types, for_actors, for_target_types, for_records, for_categories, for_outcomes, search, for_sources, for_actor_kinds, for_correlation_ids, since, until, cursor_at, cursor_id, least(greatest(coalesce(max_items, 50), 1), 1000), greatest(coalesce(skip, 0), 0);
  return result;
end;
$$;
revoke execute on function "better_supabase"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamptz, timestamptz, timestamptz, text, integer, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamptz, timestamptz, timestamptz, text, integer, boolean, integer) to authenticated, service_role;

create or replace function "better_supabase"."count_audit_events"(
  for_tenants uuid[] default null,
  for_event_types text[] default null,
  for_actors uuid[] default null,
  for_target_types text[] default null,
  for_records text[] default null,
  for_categories text[] default null,
  for_outcomes text[] default null,
  search text default null,
  for_sources text[] default null,
  for_actor_kinds text[] default null,
  for_correlation_ids text[] default null,
  since timestamptz default null,
  until timestamptz default null
)
returns bigint
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_where text := 'true';
  result bigint;
begin
  if cardinality(for_tenants) > 0 then
    v_where := v_where || $q$ and l."organization_id" = any ($1)$q$;
  end if;
  if cardinality(for_event_types) > 0 then
    v_where := v_where || $q$ and l."event_type" = any ($2)$q$;
  end if;
  if cardinality(for_actors) > 0 then
    v_where := v_where || $q$ and l."actor_id" = any ($3)$q$;
  end if;
  if cardinality(for_target_types) > 0 then
    v_where := v_where || $q$ and l."target_type" = any ($4)$q$;
  end if;
  if cardinality(for_records) > 0 then
    v_where := v_where || $q$ and l."target_id" = any ($5)$q$;
  end if;
  if cardinality(for_categories) > 0 then
    v_where := v_where || $q$ and case l."category" when 'users' then 'membership' when 'permissions' then 'access' when 'settings' then 'configuration' when 'integrations' then 'integration' when 'system' then 'ai' else l."category" end = any ($6)$q$;
  end if;
  if cardinality(for_outcomes) > 0 then
    v_where := v_where || $q$ and l."outcome" = any ($7)$q$;
  end if;
  if cardinality(for_sources) > 0 then
    v_where := v_where || $q$ and l."source" = any ($9)$q$;
  end if;
  if search <> '' then
    v_where := v_where || $q$ and concat_ws(' ', l."event_type", l."target_id") ilike '%' || replace(replace(replace($8, '\', '\\'), '%', '\%'), '_', '\_') || '%'$q$;
  end if;
  if since is not null then
    v_where := v_where || $q$ and l."occurred_at" >= $12$q$;
  end if;
  if until is not null then
    v_where := v_where || $q$ and l."occurred_at" < $13$q$;
  end if;
  execute $q$select count(*) from "centrakit"."audit_logs" l where $q$ || v_where
  into result
  using for_tenants, for_event_types, for_actors, for_target_types, for_records, for_categories, for_outcomes, search, for_sources, for_actor_kinds, for_correlation_ids, since, until;
  return result;
end;
$$;
revoke execute on function "better_supabase"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamptz, timestamptz) to authenticated, service_role;

-- The restricted details of one entry for a member with the reveal
-- permission in its tenant, or platform staff, recorded as audit.revealed.
create or replace function "better_supabase"."reveal_audit_entry"(entry text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid;
  found_entry boolean;
  details jsonb;
begin
  select true, l."organization_id" into found_entry, owner from "centrakit"."audit_logs" l where l."id"::text = entry;
  if found_entry is null or not (
    (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    or (select coalesce(better_supabase.is_platform('platform.users.manage'), false))
    or (owner is not null and coalesce(better_supabase.member_can(auth.uid(), owner, 'audit.view'), false))
  ) then
    raise exception 'No audit entry %', entry using errcode = 'P0002', hint = 'AUDIT_ENTRY_NOT_FOUND';
  end if;
  select jsonb_build_object('entry', entry, 'ip', d."ip_address", 'userAgent', d."user_agent", 'metadata', d."restricted_metadata") into details
  from "centrakit"."audit_log_restricted_details" d where d."event_id"::text = entry;
  perform "better_supabase".emit_event('audit.revealed', jsonb_build_object('organizationId', owner::text, 'entries', jsonb_build_array(entry)), 'audit-entries/' || entry, (owner)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'audit.revealed',
    category => 'security',
    target_type => 'audit_entry',
    record_id => entry,
    tenant => (owner)::uuid,
    metadata => '{}'::jsonb,
    actor_id => auth.uid()
  );
  return coalesce(details, jsonb_build_object('entry', entry));
end;
$$;
revoke execute on function "better_supabase"."reveal_audit_entry"(text) from public, anon;
grant execute on function "better_supabase"."reveal_audit_entry"(text) to authenticated, service_role;

-- The restricted details of the entries the caller may reveal, for an
-- export; entries it may not reveal are left out. One audit.revealed entry
-- per tenant lists the revealed entry ids.
create or replace function "better_supabase"."reveal_audit_entries"(entries text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  visible jsonb;
  details jsonb;
  revealed record;
begin
  select coalesce(jsonb_agg(jsonb_build_object('entry', l."id"::text, 'owner', l."organization_id")), '[]') into visible
  from "centrakit"."audit_logs" l
  where l."id"::text = any (entries)
    and (
    (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    or (select coalesce(better_supabase.is_platform('platform.users.manage'), false))
    or (l."organization_id" is not null and coalesce(better_supabase.member_can(auth.uid(), l."organization_id", 'audit.view'), false))
    );
  select coalesce(jsonb_agg(jsonb_build_object('entry', v ->> 'entry', 'ip', d."ip_address", 'userAgent', d."user_agent", 'metadata', d."restricted_metadata")), '[]') into details
  from jsonb_array_elements(visible) v
  left join "centrakit"."audit_log_restricted_details" d on d."event_id"::text = v ->> 'entry';
  for revealed in
    select v ->> 'owner' as owner, jsonb_agg(v -> 'entry') as ids
    from jsonb_array_elements(visible) v
    group by v ->> 'owner'
  loop
    perform "better_supabase".emit_event('audit.revealed', jsonb_build_object('organizationId', revealed.owner, 'entries', revealed.ids), 'audit-entries/' || coalesce(revealed.owner, 'platform'), ((revealed.owner)::uuid)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'audit.revealed',
    category => 'security',
    target_type => 'audit_entry',
    tenant => ((revealed.owner)::uuid)::uuid,
    metadata => jsonb_build_object('entries', revealed.ids),
    actor_id => auth.uid()
  );
  end loop;
  return details;
end;
$$;
revoke execute on function "better_supabase"."reveal_audit_entries"(text[]) from public, anon;
grant execute on function "better_supabase"."reveal_audit_entries"(text[]) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
