-- better-supabase module: realtime-tables
-- @bsb-block realtime-tables@1 managed
-- @bsb-hash sha256:0af558ec917620c5bceb5a0a84bcfef1062ea8c2cccb438cdf48179d2fd7ec84
-- Broadcasts a change signal (no row data) once per statement on bsb:t:<schema>.<table>[:<tenant>], or bsb:t:<schema>.<table>:u:<user> for realtime.users tables, for live queries.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Clients refetch through RLS, so the payload carries no row data.
create or replace function better_supabase.broadcast_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  base text := 'bsb:t:' || tg_table_schema || '.' || tg_table_name
    || case when tg_nargs > 1 and tg_argv[1] = 'user' then ':u' else '' end;
  payload jsonb := jsonb_build_object('schema', tg_table_schema, 'table', tg_table_name, 'operation', tg_op);
  source text;
  tenant text;
begin
  if tg_nargs = 0 or tg_argv[0] = '' then
    perform realtime.send(payload, 'change', base, true);
    return null;
  end if;
  source := case tg_op
    when 'INSERT' then format('select %1$I from new_rows', tg_argv[0])
    when 'DELETE' then format('select %1$I from old_rows', tg_argv[0])
    else format('select %1$I from new_rows union select %1$I from old_rows', tg_argv[0])
  end;
  for tenant in execute format('select distinct t.v::text from (%s) as t(v) where t.v is not null', source) loop
    perform realtime.send(payload, 'change', base || ':' || tenant, true);
  end loop;
  return null;
end;
$$;

revoke execute on function better_supabase.broadcast_changes() from public, anon, authenticated;

-- Row trigger for a topic (defineTopic) that announces the row change:
--   create trigger quotes_broadcast after insert or update or delete on public.quotes
--     for each row execute function better_supabase.broadcast_topic('organization:{organization_id}:quotes', 'quote.changed');
-- Arguments: the topic with {column} or {name=column} placeholders, the event (empty for the
-- operation), 'false' for a public topic, and the payload: 'keys' (the
-- default) sends { operation, schema, table, id, values } so clients refetch
-- through RLS; 'row' sends old_record and record, which bypasses column
-- grants. A null value skips the row; a value topics do not allow skips it
-- with a warning instead of failing the write.
-- The first row of a statement reads the primary key and the placeholder
-- columns from the catalog and keeps one query that selects only those
-- columns in a transaction setting stamped with statement_timestamp(); the
-- other rows of the statement reuse it. A bulk write still sends one message
-- per row, so a table written in bulk should use track_realtime instead.
create or replace function better_supabase.broadcast_topic()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  topic text;
  event text := tg_op;
  private boolean := true;
  mode text := 'keys';
  cache_key text := 'bsb_topic.r' || tg_relid::text || '_' || md5(tg_name);
  stamp text := statement_timestamp()::text;
  plan jsonb;
  placeholder text;
  param text;
  col text;
  placeholders text[] := '{}';
  params text[] := '{}';
  cols text[] := '{}';
  keys text[];
  id_sql text;
  vals text[];
  value text;
  payload_vals jsonb := '{}';
  id jsonb;
begin
  if tg_level <> 'ROW' then
    raise exception 'better_supabase.broadcast_topic() runs for each row'
      using errcode = '39P01';
  end if;
  if tg_when <> 'AFTER' then
    raise exception 'better_supabase.broadcast_topic() runs after the write; as a % trigger it would cancel the write', lower(tg_when)
      using errcode = '39P01';
  end if;
  if tg_nargs = 0 or tg_argv[0] = '' then
    raise exception 'better_supabase.broadcast_topic() needs the topic as its first argument'
      using errcode = '39P01';
  end if;
  topic := tg_argv[0];
  if tg_nargs > 1 and tg_argv[1] <> '' then event := tg_argv[1]; end if;
  if tg_nargs > 2 and tg_argv[2] <> '' then private := tg_argv[2]::boolean; end if;
  if tg_nargs > 3 and tg_argv[3] <> '' then mode := tg_argv[3]; end if;
  if mode not in ('keys', 'row') then
    raise exception 'better_supabase.broadcast_topic() payload must be keys or row, not %', mode
      using errcode = '22023';
  end if;
  plan := nullif(current_setting(cache_key, true), '')::jsonb;
  if plan is null or plan ->> 'stamp' is distinct from stamp then
    for placeholder in select distinct m[1] from regexp_matches(tg_argv[0], '\{([^}]+)\}', 'g') as m loop
      param := split_part(placeholder, '=', 1);
      col := coalesce(nullif(split_part(placeholder, '=', 2), ''), param);
      if not exists (
        select 1 from pg_catalog.pg_attribute a
        where a.attrelid = tg_relid and a.attname = col and a.attnum > 0 and not a.attisdropped
      ) then
        raise exception '%.% has no column % for the topic %', tg_table_schema, tg_table_name, col, tg_argv[0]
          using errcode = '42703';
      end if;
      placeholders := placeholders || placeholder;
      params := params || param;
      cols := cols || col;
    end loop;
    select array_agg(a.attname::text order by array_position(i.indkey::int2[], a.attnum))
      into keys
      from pg_catalog.pg_index i
      join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey::int2[])
      where i.indrelid = tg_relid and i.indisprimary;
    id_sql := case
      when keys is null then 'null::jsonb'
      when cardinality(keys) = 1 then format('to_jsonb(($1).%I)', keys[1])
      else 'jsonb_build_object(' || (select string_agg(format('%L, ($1).%I', k, k), ', ') from unnest(keys) as k) || ')'
    end;
    plan := jsonb_build_object(
      'stamp', stamp,
      'placeholders', to_jsonb(placeholders),
      'params', to_jsonb(params),
      'cols', to_jsonb(cols),
      'sql', format(
        'select array[%s]::text[], %s',
        coalesce((select string_agg(format('($1).%I::text', c), ', ') from unnest(cols) as c), ''),
        id_sql
      )
    );
    perform set_config(cache_key, plan::text, true);
  end if;
  execute plan ->> 'sql' using case when tg_op = 'DELETE' then old else new end into vals, id;
  for i in 1 .. coalesce(cardinality(vals), 0) loop
    value := vals[i];
    if value is null then
      return null;
    end if;
    if value !~ '^[\w.@+=-]+$' then
      raise warning 'skipped the broadcast on %: topic value % of %.%.% contains characters topics do not allow', tg_argv[0], value, tg_table_schema, tg_table_name, plan -> 'cols' ->> (i - 1);
      return null;
    end if;
    payload_vals := payload_vals || jsonb_build_object(plan -> 'params' ->> (i - 1), value);
    topic := replace(topic, '{' || (plan -> 'placeholders' ->> (i - 1)) || '}', value);
  end loop;
  if mode = 'row' then
    perform realtime.send(
      jsonb_build_object('old_record', old, 'record', new, 'operation', tg_op, 'table', tg_table_name, 'schema', tg_table_schema),
      event, topic, private
    );
    return null;
  end if;
  perform realtime.send(
    jsonb_build_object('operation', tg_op, 'schema', tg_table_schema, 'table', tg_table_name, 'id', id, 'values', payload_vals),
    event, topic, private
  );
  return null;
end;
$$;

revoke execute on function better_supabase.broadcast_topic() from public, anon, authenticated;

-- select better_supabase.track_realtime('public.customers', 'organization_id');
-- tenant_column => null broadcasts on one topic every signed-in user receives;
-- a tenant column the table lacks is an error, so no tenant table goes global.
-- user_column broadcasts per user (bsb:t:<table>:u:<user id>) instead.
drop function if exists better_supabase.track_realtime(regclass, text);
create or replace function better_supabase.track_realtime(
  target regclass,
  tenant_column text default null,
  user_column text default null
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  scope_column text := coalesce(user_column, tenant_column);
  scope_kind text := case when user_column is null then 'tenant' else 'user' end;
begin
  if scope_column is not null and not exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = target and a.attname = scope_column and a.attnum > 0 and not a.attisdropped
  ) then
    raise exception '% has no column %', target, scope_column
      using errcode = '42703',
        hint = case when user_column is null
          then 'Add the tenant column, or list the table in realtime.global to broadcast it to every signed-in user'
          else 'Check the column in realtime.users' end;
  end if;
  execute format('drop trigger if exists bsb_realtime on %s', target);
  execute format('drop trigger if exists bsb_realtime_insert on %s', target);
  execute format('drop trigger if exists bsb_realtime_update on %s', target);
  execute format('drop trigger if exists bsb_realtime_delete on %s', target);
  if scope_column is null then
    execute format(
      'create trigger bsb_realtime after insert or update or delete on %s for each statement execute function better_supabase.broadcast_changes()',
      target
    );
    return;
  end if;
  execute format(
    'create trigger bsb_realtime_insert after insert on %s referencing new table as new_rows for each statement execute function better_supabase.broadcast_changes(%L, %L)',
    target, scope_column, scope_kind
  );
  execute format(
    'create trigger bsb_realtime_update after update on %s referencing old table as old_rows new table as new_rows for each statement execute function better_supabase.broadcast_changes(%L, %L)',
    target, scope_column, scope_kind
  );
  execute format(
    'create trigger bsb_realtime_delete after delete on %s referencing old table as old_rows for each statement execute function better_supabase.broadcast_changes(%L, %L)',
    target, scope_column, scope_kind
  );
end;
$$;

create or replace function better_supabase.untrack_realtime(target regclass)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bsb_realtime on %s', target);
  execute format('drop trigger if exists bsb_realtime_insert on %s', target);
  execute format('drop trigger if exists bsb_realtime_update on %s', target);
  execute format('drop trigger if exists bsb_realtime_delete on %s', target);
end;
$$;

revoke execute on function better_supabase.track_realtime(regclass, text, text) from public, anon, authenticated;
revoke execute on function better_supabase.untrack_realtime(regclass) from public, anon, authenticated;

-- Signed-in users receive unscoped topics, topics of tenants they are members of
-- right now (checked live, not from the token claim) and
-- their own user topics (bsb:t:<table>:u:<user id>).
-- Anonymous users (signInAnonymously()) are authenticated too, but receive nothing.
drop policy if exists bsb_realtime_tables_receive on realtime.messages;
create policy bsb_realtime_tables_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
    and (select realtime.topic()) like 'bsb:t:%'
    and not coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false)
    and (
      split_part((select realtime.topic()), ':', 4) = ''
      or (split_part((select realtime.topic()), ':', 5) = '' and split_part((select realtime.topic()), ':', 4) in (
        select t.m::text from (select better_supabase.member_organization_ids() as m) t
      ))
      or (split_part((select realtime.topic()), ':', 4) = 'u'
        and split_part((select realtime.topic()), ':', 5) = (select auth.uid())::text)
    ));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
