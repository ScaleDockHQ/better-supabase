import type { BlockSqlContext } from "./context.ts";
import type { Subject } from "./subjects.ts";

import { sqlString } from "../core/template.ts";
import { SCHEMA, fail, userGrant } from "./shared.ts";

/**
 * The comment that marks a module's merge handler, so
 * `better_supabase.merge_subject_refs` finds it whatever schema or name it
 * has.
 */
export const SUBJECT_MERGE_MARKER = "better-supabase:subject-merge";

const DISPATCHER = "better_supabase.merge_subject_refs";

/** `schema.table` with `public` for a bare name, as handlers compare it. */
export function subjectTableKey(table: string): string {
  const plain = table.replaceAll('"', "");

  return plain.includes(".") ? plain : `public.${plain}`;
}

function dispatcherFunction(): string {
  return `${SCHEMA}
-- Moves every installed module's rows from record drop to record keep of the
-- subject table subject_table (schema.table): comments, attachments, tags and
-- the rest. Each module marks its handler with a comment, so this finds them
-- without naming them.
create or replace function ${DISPATCHER}(subject_table text, keep text, drop text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fn regproc;
begin
  for v_fn in
    select p.oid::regproc
    from pg_catalog.pg_proc p
    join pg_catalog.pg_description d on d.objoid = p.oid and d.classoid = 'pg_catalog.pg_proc'::regclass and d.objsubid = 0
    where d.description = ${sqlString(SUBJECT_MERGE_MARKER)}
      -- Only the owner's functions, so a marked function in a schema another
      -- role can write to never runs with this function's rights.
      and p.proowner = (select r.oid from pg_catalog.pg_roles r where r.rolname = current_user)
    order by p.oid::regproc::text
  loop
    execute format('select %s($1, $2, $3)', v_fn) using subject_table, keep, drop;
  end loop;
end;
$$;
revoke execute on function ${DISPATCHER}(text, text, text) from public, anon, authenticated;`;
}

/**
 * `sql` with `better_supabase.merge_subject_refs` defined ahead of it when it
 * calls the function and does not define it.
 */
export function withSubjectMergeFunction(sql: string): string {
  if (
    !sql.includes(`${DISPATCHER}(`) ||
    sql.includes(`function ${DISPATCHER}(`)
  ) {
    return sql;
  }

  return `${dispatcherFunction()}\n${sql}`;
}

/** A table of a module whose rows point at a subject record. */
export interface SubjectRows {
  /** The quoted table. */
  readonly table: string;
  /** The quoted subject type and id columns (text). */
  readonly type: string;
  readonly id: string;
  /**
   * The other quoted columns of a unique key that includes the subject: a row
   * of drop that keep already has under the same key is deleted, not moved.
   */
  readonly unique?: readonly string[];
}

/**
 * SQL that moves `rows` of subject type `type` (a SQL text expression) from
 * `v_drop` to `v_keep`.
 */
export function moveSubjectRows(rows: SubjectRows, type: string): string {
  const { table, type: typeColumn, id } = rows;

  const own = (alias: string, value: string): string =>
    `${alias}.${typeColumn} = ${type} and ${alias}.${id} = ${value}`;

  const duplicates =
    rows.unique === undefined
      ? ""
      : `delete from ${table} x where ${own("x", "v_drop")} and exists (select 1 from ${table} y where ${own("y", "v_keep")}${rows.unique.map((column) => ` and y.${column} is not distinct from x.${column}`).join("")});\n    `;

  return `${duplicates}update ${table} x set ${id} = v_keep where ${own("x", "v_drop")};`;
}

/**
 * The module's merge handler: for each of its subjects whose table is the
 * merged one, `move` (SQL over `v_type`, `v_keep` and `v_drop`) moves its rows.
 * Empty without subjects.
 */
export function subjectMergeHandler(
  ctx: BlockSqlContext,
  subjects: readonly (readonly [string, Subject])[],
  move: string,
): string {
  if (subjects.length === 0) {
    return "";
  }

  const fn = ctx.fn(`${ctx.module.replaceAll("-", "_")}_subject_merge`);

  const types = new Map<string, string[]>();

  for (const [type, subject] of subjects) {
    const key = subjectTableKey(subject.table);
    types.set(key, [...(types.get(key) ?? []), type]);
  }

  const cases = [...types]
    .map(
      ([table, list]) =>
        `when ${sqlString(table)} then array[${list.map((type) => sqlString(type)).join(", ")}]`,
    )
    .join(" ");

  return `
-- Moves this module's rows from one subject record to another when
-- ${DISPATCHER} merges them.
create or replace function ${fn}(subject_table text, keep text, drop text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table ${cases} else '{}'::text[] end) loop
    ${move}
  end loop;
end;
$$;
revoke execute on function ${fn}(text, text, text) from public, anon, authenticated;
comment on function ${fn}(text, text, text) is ${sqlString(SUBJECT_MERGE_MARKER)};
`;
}

/** What `recordMergeFunction` needs to merge two rows of one table. */
export interface RecordMerge {
  /** The function's default name, such as `merge_companies`. */
  readonly name: string;
  /** The logical table. */
  readonly table: string;
  /** The SQL that refuses a caller who may not merge, for tenant `tenant`. */
  readonly guard: (tenant: string) => string;
  readonly notFound: readonly [code: string, message: string];
  readonly invalid: readonly [code: string, message: string];
  /** Logical columns set to null on drop, such as a unique email. */
  readonly clear: readonly string[];
  /** Logical columns keep takes from drop when its own is null. */
  readonly fill: readonly string[];
  /**
   * SQL that moves the module's own references (`v_keep` and `v_drop` are the
   * rows; `keep` and `drop` the ids, qualified with the function name).
   */
  readonly move?: (keep: string, drop: string) => string;
  /** The `ctx.record` call, given the qualified `keep` and `drop` ids. */
  readonly record: (keep: string, drop: string) => string;
  /** The jsonb the function returns, given the qualified `keep` id. */
  readonly returns: (keep: string) => string;
}

/**
 * `name(keep uuid, drop uuid) returns jsonb`: merges row drop into row keep.
 * keep's empty `fill` columns take drop's values, drop's `clear` columns are
 * emptied, and drop is archived with `mergedInto` set. Every installed module
 * moves its rows from drop to keep through
 * `better_supabase.merge_subject_refs`. The table needs the logical columns
 * `id`, `tenant`, `mergedInto`, `archivedAt` and `updatedAt`.
 */
export function recordMergeFunction(
  ctx: BlockSqlContext,
  merge: RecordMerge,
): string {
  const table = ctx.table(merge.table);
  const col = (logical: string): string => ctx.col(merge.table, logical);
  const fn = ctx.fn(merge.name);
  const label = ctx.fnName(merge.name);
  const keep = `${label}.keep`;
  const drop = `${label}.drop`;
  const { schema, name } = ctx.tableName(merge.table);

  const clear = merge.clear.map((column) => `${col(column)} = null, `).join("");

  const fill = merge.fill.map(
    (column) =>
      `${col(column)} = coalesce(x.${col(column)}, v_drop.${col(column)})`,
  );

  const move = merge.move === undefined ? "" : `\n  ${merge.move(keep, drop)}`;

  return `
-- Merges drop into keep: keep's empty fields take drop's values, every
-- installed module moves its rows from drop to keep, and drop is archived
-- with merged_into set.
create or replace function ${fn}(keep uuid, drop uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_keep ${table};
  v_drop ${table};
begin
  select * into v_keep from ${table} x where x.${col("id")} = ${keep} for update;
  select * into v_drop from ${table} x where x.${col("id")} = ${drop} for update;
  if v_keep.${col("id")} is null or v_drop.${col("id")} is null then
    ${fail(merge.notFound[0], merge.notFound[1], "P0002")}
  end if;
  if v_keep.${col("tenant")} <> v_drop.${col("tenant")} or v_keep.${col("id")} = v_drop.${col("id")} or v_drop.${col("mergedInto")} is not null then
    ${fail(merge.invalid[0], merge.invalid[1], "22023")}
  end if;
  ${merge.guard(`v_keep.${col("tenant")}`)}
  update ${table} x set ${clear}${col("mergedInto")} = ${keep},
    ${col("archivedAt")} = coalesce(x.${col("archivedAt")}, now()), ${col("updatedAt")} = now()
  where x.${col("id")} = ${drop};${
    fill.length === 0
      ? ""
      : `\n  update ${table} x set ${fill.join(", ")}, ${col("updatedAt")} = now()\n  where x.${col("id")} = ${keep};`
  }${move}
  perform ${DISPATCHER}(${sqlString(`${schema}.${name}`)}, ${keep}::text, ${drop}::text);
  ${merge.record(keep, drop)}
  return ${merge.returns(keep)};
end;
$$;
${userGrant(`${fn}(uuid, uuid)`)}
`;
}
