import type { ModuleContext } from "../context.ts";

import { SERVICE_CALLER, fail, userGrant } from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";
import { hasColumn } from "./audit-columns.ts";

const MAX_ENTRIES = 1000;

/**
 * `revert_audit_entries(entries)`: writes the old values of row changes back,
 * newest entry first, as the caller, so the target table's policies decide.
 * It refuses with `ROW_CHANGED_SINCE` when a row no longer holds what the
 * entry wrote. Needs the row snapshots (`old` and `new`, on the log or in the
 * restricted table) and the access module. With the restricted table, the
 * caller also needs the reveal permission, since the snapshots live there.
 */
export function revert(ctx: ModuleContext, restricted: boolean): string {
  const snapshots = restricted
    ? hasColumn(ctx, "restricted", "old") && hasColumn(ctx, "restricted", "new")
    : hasColumn(ctx, "log", "old") && hasColumn(ctx, "log", "new");
  const needed = ["table", "op"].every((logical) =>
    hasColumn(ctx, "log", logical),
  );
  if (!snapshots || !needed || !ctx.installed("access")) return "";
  const log = ctx.table("log");
  const c = (logical: string) => ctx.col("log", logical);
  const snapshot = (logical: "old" | "new") =>
    restricted ? `d.${ctx.col("restricted", logical)}` : `l.${c(logical)}`;
  const join = restricted
    ? `left join ${ctx.table("restricted")} d on d.${ctx.col("restricted", "entry")} = l.${c("id")}`
    : "";
  const changed = hasColumn(ctx, "log", "changed")
    ? `to_jsonb(l.${c("changed")})`
    : "null::jsonb";
  const correlated = hasColumn(ctx, "log", "correlationId");
  const key = ctx.permission("revert", OPERATIONS["audit.revert"]);
  const mayRead = restricted
    ? ` and coalesce(better_supabase.member_can(auth.uid(), l.${c("tenant")}, ${ctx.permission("reveal", ctx.permissionKey("view", OPERATIONS["audit.view"]))}), false)`
    : "";
  const target = `to_regclass(quote_ident(split_part(l.${c("table")}, '.', 1)) || '.' || quote_ident(split_part(l.${c("table")}, '.', 2)))`;
  const written = correlated
    ? `
-- The entries the caller wrote under one correlation id, for the undo of a revert.
create or replace function ${ctx.fn("audit_entries_correlated")}(correlation text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(l.${c("id")}::text order by l.${c("id")}), '[]'::jsonb)
  from ${log} l
  where l.${c("correlationId")} = audit_entries_correlated.correlation
    and l.${c("actor")} is not distinct from auth.uid();
$$;
${userGrant(`${ctx.fn("audit_entries_correlated")}(text)`)}
`
    : "";
  return `-- The row changes the caller may revert, newest first, with their snapshots
-- and the target's key columns.
create or replace function ${ctx.fn("audit_revert_source")}(entries text[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  found_entries jsonb;
begin
  if cardinality(audit_revert_source.entries) > ${String(MAX_ENTRIES)} then
    ${fail("AUDIT_REVERT_TOO_MANY", `revert at most ${String(MAX_ENTRIES)} entries at once`, "22023")}
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', l.${c("id")}::text,
      'table', ${target}::text,
      'op', l.${c("op")},
      'old', ${snapshot("old")},
      'new', ${snapshot("new")},
      'changed', ${changed},
      'keys', to_jsonb(coalesce(
        (select a.key_columns from better_supabase.audited_tables a where a.target = ${target}),
        (select array_agg(att.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute att on att.attrelid = i.indrelid and att.attnum = k.attnum
         where i.indrelid = ${target} and i.indisprimary)
      ))
    ) order by l.${c("occurredAt")} desc, l.${c("id")} desc), '[]'::jsonb)
  into found_entries
  from ${log} l
  ${join}
  where l.${c("id")}::text = any (audit_revert_source.entries)
    and (${SERVICE_CALLER}
      or (l.${c("tenant")} is not null and coalesce(better_supabase.member_can(auth.uid(), l.${c("tenant")}, ${key}), false)${mayRead}));
  if jsonb_array_length(found_entries) <> cardinality(array(select distinct e from unnest(audit_revert_source.entries) e)) then
    ${fail("AUDIT_ENTRY_NOT_FOUND", "an entry is missing or not yours to revert", "P0002")}
  end if;
  return found_entries;
end;
$$;
${userGrant(`${ctx.fn("audit_revert_source")}(text[])`)}
${written}
-- Writes the old values of row changes back as the caller, newest entry
-- first, all or nothing.
create or replace function ${ctx.fn("revert_audit_entries")}(entries text[])
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  entry jsonb;
  target regclass;
  v_old jsonb;
  v_new jsonb;
  current_row jsonb;
  columns text[];
  key_match text;
  affected integer;
  reverted integer := 0;
  v_correlation text := 'revert:' || gen_random_uuid()::text;
  v_previous text := current_setting('better_supabase.correlation_id', true);
  undo_entries jsonb := null;
begin
  perform set_config('better_supabase.correlation_id', v_correlation, true);
  for entry in select value from jsonb_array_elements(${ctx.fn("audit_revert_source")}(revert_audit_entries.entries)) loop
    target := (entry ->> 'table')::regclass;
    v_old := entry -> 'old';
    v_new := entry -> 'new';
    if target is null or entry ->> 'op' not in ('insert', 'update', 'delete') or jsonb_typeof(entry -> 'keys') <> 'array' then
      ${fail("AUDIT_ENTRY_NOT_REVERTIBLE", "the entry is not a row change of a table that still exists", "22023")}
    end if;
    select string_agg(format('t.%I::text is not distinct from %L', k, coalesce(v_new, v_old) ->> k), ' and ')
    into key_match
    from jsonb_array_elements_text(entry -> 'keys') k;
    execute format('select to_jsonb(t) from %s t where %s', target, key_match) into current_row;
    case entry ->> 'op'
      when 'update' then
        select array_agg(k) into columns
        from jsonb_array_elements_text(coalesce(entry -> 'changed', (select jsonb_agg(n) from jsonb_object_keys(v_new) n))) k
        where v_new ? k and v_old ? k;
        if columns is null then
          ${fail("AUDIT_ENTRY_NOT_REVERTIBLE", "the entry changed no column it can restore", "22023")}
        end if;
        if exists (select 1 from unnest(columns) k where v_old -> k = '"[redacted]"'::jsonb or v_new -> k = '"[redacted]"'::jsonb) then
          ${fail("AUDIT_ENTRY_REDACTED", "the entry holds redacted values", "22023")}
        end if;
        if current_row is null or exists (
          select 1 from unnest(columns) k where current_row -> k is distinct from v_new -> k
        ) then
          ${fail("ROW_CHANGED_SINCE", "the row changed after this entry", "P0001")}
        end if;
        execute format(
          'update %s t set %s from jsonb_populate_record(null::%s, $1) o where %s',
          target,
          (select string_agg(format('%I = o.%I', k, k), ', ') from unnest(columns) k),
          target,
          key_match
        ) using v_old;
      when 'insert' then
        if current_row is null or exists (
          select 1 from jsonb_each(v_new) n
          where n.value <> '"[redacted]"'::jsonb and current_row -> n.key is distinct from n.value
        ) then
          ${fail("ROW_CHANGED_SINCE", "the row changed after this entry", "P0001")}
        end if;
        execute format('delete from %s t where %s', target, key_match);
      when 'delete' then
        if current_row is not null then
          ${fail("ROW_CHANGED_SINCE", "a row with this key exists again", "P0001")}
        end if;
        if exists (select 1 from jsonb_each(v_old) o where o.value = '"[redacted]"'::jsonb) then
          ${fail("AUDIT_ENTRY_REDACTED", "the entry holds redacted values", "22023")}
        end if;
        select array_agg(att.attname::text order by att.attnum) into columns
        from pg_catalog.pg_attribute att
        where att.attrelid = target and att.attnum > 0 and not att.attisdropped
          and att.attgenerated = '' and v_old ? att.attname::text;
        execute format(
          'insert into %s (%s) overriding system value select %s from jsonb_populate_record(null::%s, $1) o',
          target,
          (select string_agg(format('%I', k), ', ') from unnest(columns) k),
          (select string_agg(format('o.%I', k), ', ') from unnest(columns) k),
          target
        ) using v_old;
    end case;
    get diagnostics affected = row_count;
    if affected <> 1 then
      ${fail("AUDIT_REVERT_FORBIDDEN", "not allowed to change this row")}
    end if;
    reverted := reverted + 1;
  end loop;
  perform set_config('better_supabase.correlation_id', coalesce(v_previous, ''), true);
  ${correlated ? `undo_entries := ${ctx.fn("audit_entries_correlated")}(v_correlation);` : "null;"}
  return jsonb_build_object('reverted', reverted, 'entries', undo_entries);
end;
$$;
${userGrant(`${ctx.fn("revert_audit_entries")}(text[])`)}`;
}
