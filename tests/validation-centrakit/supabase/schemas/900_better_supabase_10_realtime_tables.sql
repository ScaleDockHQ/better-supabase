-- better-supabase module: realtime-tables (0.8.0)
-- @bs-module realtime-tables@1 managed
-- Broadcasts a change signal (no row data) once per statement on bs:t:<schema>.<table>[:<tenant>], or bs:t:<schema>.<table>:u:<user> for realtime.users tables, for live queries.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
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
  base text := 'bs:t:' || tg_table_schema || '.' || tg_table_name
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

-- Row trigger for a topic (defineTopic) that carries the row change:
--   create trigger quotes_broadcast after insert or update or delete on public.quotes
--     for each row execute function better_supabase.broadcast_topic('organization:{organization_id}:quotes', 'quote.changed');
-- Arguments: the topic with {column} placeholders, the event (empty for the
-- operation) and 'false' for a public topic. A null value skips the row.
create or replace function better_supabase.broadcast_topic()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  topic text;
  event text := tg_op;
  private boolean := true;
  placeholder text;
  value text;
begin
  if tg_level <> 'ROW' then
    raise exception 'better_supabase.broadcast_topic() runs for each row'
      using errcode = '39P01';
  end if;
  if tg_nargs = 0 or tg_argv[0] = '' then
    raise exception 'better_supabase.broadcast_topic() needs the topic as its first argument'
      using errcode = '39P01';
  end if;
  topic := tg_argv[0];
  if tg_nargs > 1 and tg_argv[1] <> '' then event := tg_argv[1]; end if;
  if tg_nargs > 2 then private := tg_argv[2]::boolean; end if;
  for placeholder in select distinct m[1] from regexp_matches(tg_argv[0], '\{([^}]+)\}', 'g') as m loop
    if not rec ? placeholder then
      raise exception '%.% has no column % for the topic %', tg_table_schema, tg_table_name, placeholder, tg_argv[0]
        using errcode = '42703';
    end if;
    value := rec ->> placeholder;
    if value is null then
      return null;
    end if;
    if value !~ '^[\w.@+=-]+$' then
      raise exception 'topic value % of %.%.% contains characters topics do not allow', value, tg_table_schema, tg_table_name, placeholder
        using errcode = '22023';
    end if;
    topic := replace(topic, '{' || placeholder || '}', value);
  end loop;
  perform realtime.send(
    jsonb_build_object('old_record', old, 'record', new, 'operation', tg_op, 'table', tg_table_name, 'schema', tg_table_schema),
    event, topic, private
  );
  return null;
end;
$$;

revoke execute on function better_supabase.broadcast_topic() from public, anon, authenticated;

-- select better_supabase.track_realtime('public.customers', 'organization_id');
-- tenant_column => null broadcasts on one topic every signed-in user receives;
-- a tenant column the table lacks is an error, so no tenant table goes global.
-- user_column broadcasts per user (bs:t:<table>:u:<user id>) instead.
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
  execute format('drop trigger if exists bs_realtime on %s', target);
  execute format('drop trigger if exists bs_realtime_insert on %s', target);
  execute format('drop trigger if exists bs_realtime_update on %s', target);
  execute format('drop trigger if exists bs_realtime_delete on %s', target);
  if scope_column is null then
    execute format(
      'create trigger bs_realtime after insert or update or delete on %s for each statement execute function better_supabase.broadcast_changes()',
      target
    );
    return;
  end if;
  execute format(
    'create trigger bs_realtime_insert after insert on %s referencing new table as new_rows for each statement execute function better_supabase.broadcast_changes(%L, %L)',
    target, scope_column, scope_kind
  );
  execute format(
    'create trigger bs_realtime_update after update on %s referencing old table as old_rows new table as new_rows for each statement execute function better_supabase.broadcast_changes(%L, %L)',
    target, scope_column, scope_kind
  );
  execute format(
    'create trigger bs_realtime_delete after delete on %s referencing old table as old_rows for each statement execute function better_supabase.broadcast_changes(%L, %L)',
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
  execute format('drop trigger if exists bs_realtime on %s', target);
  execute format('drop trigger if exists bs_realtime_insert on %s', target);
  execute format('drop trigger if exists bs_realtime_update on %s', target);
  execute format('drop trigger if exists bs_realtime_delete on %s', target);
end;
$$;

revoke execute on function better_supabase.track_realtime(regclass, text, text) from public, anon, authenticated;
revoke execute on function better_supabase.untrack_realtime(regclass) from public, anon, authenticated;

-- Signed-in users receive unscoped topics, topics of their active tenant and
-- their own user topics (bs:t:<table>:u:<user id>).
-- Anonymous users (signInAnonymously()) are authenticated too, but receive nothing.
drop policy if exists bs_realtime_tables_receive on realtime.messages;
create policy bs_realtime_tables_receive on realtime.messages for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (select realtime.topic()) like 'bs:t:%'
    and not coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false)
    and (
      split_part((select realtime.topic()), ':', 4) = ''
      or (split_part((select realtime.topic()), ':', 5) = '' and split_part((select realtime.topic()), ':', 4) = coalesce(
        (select auth.jwt()) ->> 'tenant_id',
        (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id',
        ''
      ))
      or (split_part((select realtime.topic()), ':', 4) = 'u'
        and split_part((select realtime.topic()), ':', 5) = (select auth.uid())::text)
    )
  );

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
