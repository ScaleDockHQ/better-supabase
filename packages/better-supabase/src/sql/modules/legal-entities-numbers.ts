import type { BlockSqlContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/** A document table whose numbers count per legal entity. */
export interface NumberedTable {
  /** The `options.on` key: `invoices`, `quotes` or `orders`. */
  readonly kind: string;
  /** The module that owns the table. */
  readonly own: BlockSqlContext;
  readonly table: string;
  /** The logical number columns the table has. */
  readonly columns: readonly string[];
  /**
   * The logical columns the number key holds besides the organization and the
   * number, such as the direction and kind of an invoice.
   */
  readonly scope: readonly string[];
}

const LEGAL_ENTITY_COLUMN = "legal_entity_id";

/** `x.a, x.b` for the scope columns, with a leading comma when there are some. */
function scopeList(numbered: NumberedTable, alias: string): string {
  return numbered.scope
    .map((logical) => `, ${alias}.${numbered.own.col(numbered.table, logical)}`)
    .join("");
}

/** `and x.a is not distinct from y.a ...` for the scope columns. */
function scopeMatch(
  numbered: NumberedTable,
  left: string,
  right: string,
): string {
  return numbered.scope
    .map((logical) => {
      const column = numbered.own.col(numbered.table, logical);

      return ` and ${left}.${column} is not distinct from ${right}.${column}`;
    })
    .join("");
}

/** The name of the trigger and function that guard one table's numbers. */
function guardName(table: NumberedTable): string {
  return `bsb_${table.own.tableName(table.table).name}_entity_numbers`;
}

/**
 * One key for a document without a legal entity and a document of the default
 * entity. The unique index keeps a number once per entity, with null apart from
 * an explicit default entity, because the default is a row that can change.
 * This trigger closes that gap: a number may not be held by a document of the
 * default entity and by one without an entity at the same time, which is the
 * single series `number_scope` counts for both. A transaction lock per number
 * makes two writers wait for each other.
 */
export function numberGuardSql(
  ctx: BlockSqlContext,
  numbered: NumberedTable,
): string {
  const { own, table, columns } = numbered;
  const entities = ctx.table("entities");
  const e = (column: string): string => ctx.col("entities", column);
  const c = (column: string): string => own.col(table, column);
  const name = guardName(numbered);
  const fn = ctx.fn(name);
  const target = own.table(table);
  const kind = sqlString(numbered.kind);

  const checks = columns
    .map(
      (column) => `  if new.${c(column)} is not null then
    perform pg_advisory_xact_lock(hashtextextended('bsb_entity_number:' || ${sqlString(own.tableName(table).name)} || ':' || new.${c("tenant")}::text || ':${column}:' || new.${c(column)}::text, 0));
    if exists (
      select 1 from ${target} x
      where x.${c("tenant")} = new.${c("tenant")} and x.${c(column)} = new.${c(column)} and x.${c("id")} <> new.${c("id")}${scopeMatch(numbered, "x", "new")}
        and (x.${LEGAL_ENTITY_COLUMN} is null or x.${LEGAL_ENTITY_COLUMN} = v_default)
    ) then
      raise exception '% % % is already used: a document without a legal entity and a document of the default legal entity share one series', ${kind}, ${sqlString(column)}, new.${c(column)}
        using errcode = '23505', hint = 'LEGAL_ENTITY_NUMBER_TAKEN';
    end if;
  end if;`,
    )
    .join("\n");

  const updateOf = [
    ...columns.map(c),
    ...numbered.scope.map(c),
    LEGAL_ENTITY_COLUMN,
  ].join(", ");

  return `
-- A number may not be held twice by the default legal entity and by documents
-- without one (null stands for the default entity).
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_default uuid;
begin
  select e.${e("id")} into v_default from ${entities} e where e.${e("tenant")} = new.${c("tenant")} and e.${e("isDefault")};
  if new.${LEGAL_ENTITY_COLUMN} is not null and new.${LEGAL_ENTITY_COLUMN} is distinct from v_default then
    return new;
  end if;
${checks}
  return new;
end;
$$;
revoke execute on function ${fn}() from public, anon, authenticated;
drop trigger if exists ${sqlIdent(name)} on ${target};
create trigger ${sqlIdent(name)} before insert or update of ${updateOf} on ${target}
  for each row execute function ${fn}();
-- Documents that already share a number across the null and default spellings
-- stay as they are; the guard only checks new and changed rows. They are
-- listed by legal_entities_disable_check.
do $$
begin
  if exists (
    select 1 from ${target} x
    join ${entities} d on d.${e("tenant")} = x.${c("tenant")} and d.${e("isDefault")} and x.${LEGAL_ENTITY_COLUMN} = d.${e("id")}
    join ${target} y on y.${c("tenant")} = x.${c("tenant")} and y.${LEGAL_ENTITY_COLUMN} is null and (${columns.map((column) => `x.${c(column)} = y.${c(column)}`).join(" or ")})${scopeMatch(numbered, "x", "y")}
  ) then
    raise warning '${table} holds numbers twice for the default legal entity and for documents without one; list them with legal_entities_disable_check and renumber one of each pair'
      using hint = 'LEGAL_ENTITY_NUMBER_DUPLICATE';
  end if;
end $$;`;
}

/**
 * Moving the default to another entity merges the series of the new default and
 * of the documents without an entity. The switch refuses to start when that
 * would give two documents one number.
 */
export function defaultSwitchGuardSql(
  ctx: BlockSqlContext,
  tables: readonly NumberedTable[],
): string {
  if (tables.length === 0) {
    return "";
  }

  const entities = ctx.table("entities");
  const e = (column: string): string => ctx.col("entities", column);
  const fn = ctx.fn("legal_entity_default_guard");

  const checks = tables
    .flatMap((numbered) =>
      numbered.columns.map((column) => {
        const c = (logical: string): string =>
          numbered.own.col(numbered.table, logical);

        return `  select x.${c(column)}::text into v_number
  from ${numbered.own.table(numbered.table)} x
  where x.${c("tenant")} = new.${e("tenant")} and x.${c(column)} is not null
    and (x.${LEGAL_ENTITY_COLUMN} is null or x.${LEGAL_ENTITY_COLUMN} = new.${e("id")})
  group by x.${c(column)}${scopeList(numbered, "x")} having count(*) > 1
  limit 1;
  if v_number is not null then
    raise exception 'can not make this legal entity the default: % % exists for it and for documents without a legal entity', ${sqlString(numbered.kind)}, v_number
      using errcode = '23505', hint = 'LEGAL_ENTITY_DEFAULT_NUMBER_CONFLICT';
  end if;`;
      }),
    )
    .join("\n");

  return `
-- Making an entity the default merges its numbers with those of documents that
-- have no legal entity, so the switch needs them to be distinct.
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_number text;
begin
${checks}
  return new;
end;
$$;
revoke execute on function ${fn}() from public, anon, authenticated;
drop trigger if exists bsb_legal_entity_default_guard on ${entities};
create trigger bsb_legal_entity_default_guard after update of ${e("isDefault")} on ${entities}
  for each row when (new.${e("isDefault")} and not old.${e("isDefault")}) execute function ${fn}();`;
}

/**
 * `legal_entities_disable_check`: what turning `options.on` off for a kind
 * would collide with. Without the entity, a number is unique per organization,
 * so a number that two entities hold would break that key.
 */
export function disableCheckSql(
  ctx: BlockSqlContext,
  tables: readonly NumberedTable[],
): string {
  if (tables.length === 0) {
    return "";
  }

  const fn = ctx.fn("legal_entities_disable_check");
  const entities = ctx.table("entities");
  const e = (column: string): string => ctx.col("entities", column);

  const manage = ctx.permission(
    "manage",
    moduleOperations("legal-entities").manage,
  );

  const collisions = tables.flatMap((numbered) =>
    numbered.columns.map((column) => {
      const c = (logical: string): string =>
        numbered.own.col(numbered.table, logical);

      const entity = `coalesce(x.${LEGAL_ENTITY_COLUMN}, (select d.${e("id")} from ${entities} d where d.${e("tenant")} = x.${c("tenant")} and d.${e("isDefault")}))`;

      return `select ${sqlString(numbered.kind)} as kind, ${sqlString(column)} as "column", x.${c(column)}::text as value,
      count(*) as documents, jsonb_agg(distinct ${entity}) as entities
    from ${numbered.own.table(numbered.table)} x
    where x.${c("tenant")} = legal_entities_disable_check.tenant and x.${c(column)} is not null
    group by x.${c(column)}${scopeList(numbered, "x")}
    having count(*) > 1`;
    }),
  );

  const duplicates = tables.flatMap((numbered) =>
    numbered.columns.map((column) => {
      const c = (logical: string): string =>
        numbered.own.col(numbered.table, logical);

      return `select ${sqlString(numbered.kind)} as kind, ${sqlString(column)} as "column", x.${c(column)}::text as value, count(*) as documents
    from ${numbered.own.table(numbered.table)} x
    where x.${c("tenant")} = legal_entities_disable_check.tenant and x.${c(column)} is not null
      and (x.${LEGAL_ENTITY_COLUMN} is null or x.${LEGAL_ENTITY_COLUMN} = (select d.${e("id")} from ${entities} d where d.${e("tenant")} = x.${c("tenant")} and d.${e("isDefault")}))
    group by x.${c(column)}${scopeList(numbered, "x")}
    having count(*) > 1`;
    }),
  );

  const listed = (queries: readonly string[], keys: string): string =>
    `coalesce((select jsonb_agg(jsonb_build_object(${keys}) order by q.kind, q."column", q.value) from (
    ${queries.join("\n    union all\n    ")}
  ) q), '[]'::jsonb)`;

  return `
-- Lists what blocks legal-entities from handing a number back to the
-- organization: collisions are numbers that more than one legal entity holds
-- (the default entity and documents without an entity count as one), so the
-- per-organization key can't be restored until one of each pair is renumbered.
-- defaultCollisions are numbers the default entity and documents without an
-- entity hold twice already. ok is true when there are no collisions. Needs
-- legal-entities.manage.
create or replace function ${fn}(tenant ${ctx.idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_collisions jsonb;
  v_defaults jsonb;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "legal_entities_disable_check.tenant", manage)}) then
    ${fail("LEGAL_ENTITY_FORBIDDEN", "not allowed to manage legal entities", "42501")}
  end if;
  v_collisions := ${listed(collisions, `'kind', q.kind, 'column', q."column", 'value', q.value, 'documents', q.documents, 'legalEntityIds', q.entities`)};
  v_defaults := ${listed(duplicates, `'kind', q.kind, 'column', q."column", 'value', q.value, 'documents', q.documents`)};
  return jsonb_build_object('ok', jsonb_array_length(v_collisions) = 0, 'collisions', v_collisions, 'defaultCollisions', v_defaults);
end;
$$;
${userGrant(`${fn}(${ctx.idType})`)}`;
}

/**
 * The tables of a kind whose `options.on` is off while the table still has a
 * `legal_entity_id` column: the per-entity number key goes back to one per
 * organization, after a check that no number collides. The column and its data
 * stay; the migration the diff writes is the place to drop them.
 */
export function restoreNumberKeysSql(
  ctx: BlockSqlContext,
  table: NumberedTable,
): string {
  const { own } = table;
  const target = own.table(table.table);
  const name = guardName(table);

  const physical = (logical: string): string =>
    sqlString(own.colName(table.table, logical));

  const fn = ctx.fn(name);

  return `
-- options.on no longer names ${table.kind}: numbers are unique per organization
-- again. The keys go back only when no number is used by two legal entities.
do $$
declare
  v_key record;
  v_taken text;
begin
  if to_regclass('${target}') is null or not exists (
    select 1 from pg_attribute where attrelid = '${target}'::regclass and attname = '${LEGAL_ENTITY_COLUMN}' and not attisdropped
  ) then
    return;
  end if;
  for v_key in
    select ic.relname as index_name, i.indexrelid::regclass::text as index_ref, c.conname,
      (select string_agg(quote_ident(a.attname), ', ' order by k.ord)
       from unnest(i.indkey::int2[]) with ordinality k(attnum, ord)
       join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum where k.attnum > 0) as cols,
      (select string_agg(quote_ident(a.attname) || ' is not null', ' and ' order by k.ord)
       from unnest(i.indkey::int2[]) with ordinality k(attnum, ord)
       join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum where k.attnum > 0) as present
    from pg_index i
    join pg_class ic on ic.oid = i.indexrelid
    left join pg_constraint c on c.conindid = i.indexrelid and c.contype = 'u'
    where i.indrelid = '${target}'::regclass and i.indisunique and not i.indisprimary and i.indpred is null
      and pg_get_expr(i.indexprs, i.indrelid) like '%${LEGAL_ENTITY_COLUMN}%'
      and (select array_agg(a.attname::text) from pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey::int2[]))
        && array[${table.columns.map(physical).join(", ")}]
  loop
    execute format('select row(%s)::text from ${target} where %s group by %s having count(*) > 1 limit 1', v_key.cols, v_key.present, v_key.cols) into v_taken;
    if v_taken is not null then
      raise exception 'can not turn legal entities off for ${table.kind}: numbers are held by more than one legal entity (for example %). List them with legal_entities_disable_check while the option is on, renumber one of each pair, then turn the option off', v_taken
        using errcode = '23505', hint = 'LEGAL_ENTITIES_DISABLE_COLLISION';
    end if;
    execute format('drop index %s', v_key.index_ref);
    execute format('create unique index %I on ${target} (%s)', v_key.index_name, v_key.cols);
  end loop;
end $$;
drop trigger if exists ${sqlIdent(name)} on ${target};
drop function if exists ${fn}();`;
}
