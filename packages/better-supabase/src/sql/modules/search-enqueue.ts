import type { BlockSqlContext } from "../context.ts";

import { lockTable, serviceGrant } from "../shared.ts";

/**
 * The records an import run changed, until it closes. It lives in
 * `better_supabase` because `search_enqueue` writes it for any run.
 */
export const enqueueTable: string = `-- The records an import run changed (search_enqueue while
-- better_supabase.import_run is set), until finish_import_run or
-- cancel_import_run indexes each once through search_refresh_run.
create table if not exists better_supabase.import_search_dirty (
  run_id uuid not null,
  subject_type text not null,
  subject_id text not null,
  primary key (run_id, subject_type, subject_id)
);
${lockTable("better_supabase.import_search_dirty")}`;

/**
 * How the index triggers hand records to `search_refresh`: at once, at the end
 * of an import batch's transaction, or when the import run closes (ADR 0421,
 * ADR 0844), and the row and statement trigger functions that call it.
 */
export function enqueueFunctions(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);

  return `-- Runs as its caller (the definer trigger functions and import_upsert_batch
-- call it), so it adds no definer function. Indexes a record now, or, with
-- better_supabase.search_deferred on (import_upsert_batch sets it), notes the
-- key for later: in import_search_dirty when an import run is set, so the run
-- indexes it once when it closes, and otherwise once, one line per key, in one
-- of 256 transaction-local settings (better_supabase.search_dirty_<hash>) so
-- search_refresh_dirty indexes it at the end of the transaction. A setting
-- holds a 256th of the keys: one text setting rewrote the whole list on every
-- note.
create or replace function ${fn("search_enqueue")}(subject_type text, subject_id text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := search_enqueue.subject_type || E'\\x1f' || search_enqueue.subject_id;
  v_name text := 'better_supabase.search_dirty_' || (hashtext(v_key) & 255)::text;
  v_dirty text;
  v_run text := nullif(current_setting('better_supabase.import_run', true), '');
begin
  if coalesce(current_setting('better_supabase.search_deferred', true), '') = 'on' and v_run is not null then
    insert into better_supabase.import_search_dirty (run_id, subject_type, subject_id)
    values (v_run::uuid, search_enqueue.subject_type, search_enqueue.subject_id)
    on conflict do nothing;
  elsif coalesce(current_setting('better_supabase.search_deferred', true), '') = 'on' then
    v_dirty := coalesce(current_setting(v_name, true), '');
    if position(E'\\n' || v_key || E'\\n' in E'\\n' || v_dirty) = 0 then
      perform set_config(v_name, v_dirty || v_key || E'\\n', true);
    end if;
  else
    perform ${fn("search_refresh")}(search_enqueue.subject_type, search_enqueue.subject_id);
  end if;
end;
$$;
revoke execute on function ${fn("search_enqueue")}(text, text) from public, anon, authenticated;

-- Indexes every record noted by search_enqueue in this transaction, once each.
-- Returns how many it indexed.
create or replace function ${fn("search_refresh_dirty")}()
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_bucket integer;
  v_name text;
  v_dirty text;
  v_line text;
begin
  for v_bucket in 0..255 loop
    v_name := 'better_supabase.search_dirty_' || v_bucket::text;
    v_dirty := coalesce(current_setting(v_name, true), '');
    if v_dirty <> '' then
      perform set_config(v_name, '', true);
      for v_line in select l from string_to_table(v_dirty, E'\\n') l where l <> '' loop
        if ${fn("search_refresh")}(split_part(v_line, E'\\x1f', 1), split_part(v_line, E'\\x1f', 2)) then
          v_count := v_count + 1;
        end if;
      end loop;
    end if;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("search_refresh_dirty")}()`)}

-- Indexes every record an import run noted (import_search_dirty) once, and
-- clears the run's notes. finish_import_run and cancel_import_run call it.
create or replace function ${fn("search_refresh_run")}(run uuid)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer := 0;
  v_row record;
begin
  for v_row in
    delete from better_supabase.import_search_dirty d
    where d.run_id = search_refresh_run.run
    returning d.subject_type, d.subject_id
  loop
    if ${fn("search_refresh")}(v_row.subject_type, v_row.subject_id) then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("search_refresh_run")}(uuid)`)}

create or replace function ${fn("search_index_row")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) ->> tg_argv[1] end;
  v_new text := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) ->> tg_argv[1] end;
begin
  if v_old is not null and v_old is distinct from v_new then
    perform ${fn("search_enqueue")}(tg_argv[0], v_old);
  end if;
  if v_new is not null then
    perform ${fn("search_enqueue")}(tg_argv[0], v_new);
  end if;
  return null;
end;
$$;
revoke execute on function ${fn("search_index_row")}() from public, anon, authenticated;

-- search_enqueue for many ids of one type, as the statement triggers call it.
create or replace function ${fn("search_enqueue_many")}(subject_type text, subject_ids text[])
returns void
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id text;
  v_run text := nullif(current_setting('better_supabase.import_run', true), '');
begin
  if coalesce(current_setting('better_supabase.search_deferred', true), '') = 'on' and v_run is not null then
    insert into better_supabase.import_search_dirty (run_id, subject_type, subject_id)
    select v_run::uuid, search_enqueue_many.subject_type, i.id
    from unnest(search_enqueue_many.subject_ids) i(id)
    on conflict do nothing;
    return;
  end if;
  foreach v_id in array coalesce(search_enqueue_many.subject_ids, '{}'::text[]) loop
    perform ${fn("search_enqueue")}(search_enqueue_many.subject_type, v_id);
  end loop;
end;
$$;
revoke execute on function ${fn("search_enqueue_many")}(text, text[]) from public, anon, authenticated;

-- The statement form of search_index_row (search.statement): one call per
-- statement reads the changed ids from the transition tables. tg_argv[2] lists
-- the columns whose change re-indexes an updated row; empty means any change.
create or replace function ${fn("search_index_stmt")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text := tg_argv[1];
  v_columns text[] := string_to_array(nullif(coalesce(tg_argv[2], ''), ''), ',');
  v_ids text[];
begin
  if tg_op = 'INSERT' then
    select array_agg(distinct to_jsonb(n) ->> v_key) into v_ids from new_rows n;
  elsif tg_op = 'DELETE' then
    select array_agg(distinct to_jsonb(o) ->> v_key) into v_ids from old_rows o;
  else
    with o as (select to_jsonb(r) as j from old_rows r),
      n as (select to_jsonb(r) as j from new_rows r)
    select array_agg(distinct x.id) into v_ids
    from (
      select n.j ->> v_key as id
      from n left join o on o.j ->> v_key = n.j ->> v_key
      where o.j is null or v_columns is null
        or exists (select 1 from unnest(v_columns) c where o.j -> c is distinct from n.j -> c)
      union
      select o.j ->> v_key
      from o left join n on n.j ->> v_key = o.j ->> v_key
      where n.j is null
    ) x;
  end if;
  perform ${fn("search_enqueue_many")}(tg_argv[0], array_remove(v_ids, null));
  return null;
end;
$$;
revoke execute on function ${fn("search_index_stmt")}() from public, anon, authenticated;`;
}
