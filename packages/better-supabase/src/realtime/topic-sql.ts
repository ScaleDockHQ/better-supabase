import type { TableMeta } from "../schema/types.ts";

import { accessCheck, fillTemplate, isScopeName } from "../core/access-sql.ts";
import { sqlIdent, sqlString } from "../core/template.ts";

const segmentSql = (index: number): string =>
  `split_part((select realtime.topic()), ':', ${String(index)})`;

export interface TopicPermissionSql {
  /** `defineTopic(<template>)`, for errors. */
  readonly where: string;
  readonly key: string;
  /** 1-based segment holding the instance id. */
  readonly idSegment: number;
  /** 1-based segment holding the tenant id, when the topic has one. */
  readonly tenantSegment: number | undefined;
  readonly resource: string;
  readonly scope: string;
  /** The provider's instance template, when one is configured. */
  readonly permitted: string | undefined;
}

/**
 * The receive condition for a topic's instance permission. With the provider's
 * `permitted` template it asks about the instance in the topic (`{permission}`,
 * `{id}` and `{tenant}` as text, `{resource}` as a text literal, `{scope}`
 * unquoted). Without one it falls back to the access contract's tenant check,
 * `tenant_ids_with(permission)` on the tenant segment, and a topic without a
 * tenant segment is refused.
 */
export function topicPermissionSql(input: TopicPermissionSql): string {
  const { where, key, tenantSegment } = input;

  const tenant =
    tenantSegment === undefined ? undefined : segmentSql(tenantSegment);

  if (input.permitted !== undefined) {
    if (!isScopeName(input.scope)) {
      throw new TypeError(
        `${where}: invalid permission scope "${input.scope}"`,
      );
    }

    return `coalesce((${fillTemplate(
      `${where} authorization.functions.permitted`,
      input.permitted,
      {
        permission: sqlString(key),
        id: segmentSql(input.idSegment),
        tenant: tenant ?? "null::text",
        resource: sqlString(input.resource),
        scope: input.scope,
      },
    )}), false)`;
  }

  if (tenant === undefined) {
    throw new TypeError(
      `${where}: permission "${key}" needs the authorization provider's \`permitted\` template, or a tenant segment for the tenant check`,
    );
  }

  return accessCheck(where, {}, key, tenant);
}

export type AnyTriggerValue =
  | string
  | {
      readonly from: string;
      readonly via: AnyTriggerValue;
      readonly select: string;
      readonly key?: string;
    };

export const splitTable = (table: string): readonly [string, string] =>
  table.includes(".")
    ? [table.slice(0, table.indexOf(".")), table.slice(table.indexOf(".") + 1)]
    : ["public", table];

function columnSql(meta: TableMeta, column: string, where: string): string {
  const db = meta.columns[column]?.db;

  if (!db) {
    throw new TypeError(
      `defineTopic: no column for ${where} on "${meta.key}" ("${column}")`,
    );
  }

  return sqlIdent(db);
}

interface LookupTarget {
  readonly relation: string;
  readonly key: string;
  readonly select: string;
}

function lookupTarget(
  tables: Readonly<Record<string, TableMeta | undefined>>,
  value: Exclude<AnyTriggerValue, string>,
  where: string,
): LookupTarget {
  const joined = tables[value.from];

  if (!joined) {
    throw new TypeError(
      `defineTopic: unknown table "${value.from}" for ${where}`,
    );
  }

  const key =
    value.key ??
    (joined.primaryKey.length === 1 ? joined.primaryKey[0] : undefined);

  if (key === undefined) {
    throw new TypeError(
      `defineTopic: "${value.from}" has no single-column primary key; name its key for ${where}`,
    );
  }

  return {
    relation: `${sqlIdent(joined.schema)}.${sqlIdent(joined.name)}`,
    key: columnSql(joined, key, where),
    select: columnSql(joined, value.select, where),
  };
}

function rawLookupTarget(
  value: Exclude<AnyTriggerValue, string>,
): LookupTarget {
  const [schema, name] = splitTable(value.from);

  return {
    relation: `${sqlIdent(schema)}.${sqlIdent(name)}`,
    key: sqlIdent(value.key ?? "id"),
    select: sqlIdent(value.select),
  };
}

/** One parent row a generated function reads into a record variable. */
export interface TriggerLookupSql {
  /** The record variable, `lk_<n>`; a column is `lk_<n>."column"`. */
  readonly name: string;
  /** The quoted `schema.table`. */
  readonly relation: string;
  readonly key: string;
  /** The quoted columns read from the row. */
  readonly columns: readonly string[];
  /** The value it joins on: a `rec` column or an earlier lookup's column. */
  readonly via: string;
}

/**
 * The lookups of one generated function. Each parent row is read once per
 * changed row, with every column the topics, values and payload need from it,
 * and a row comes before the rows that join through it.
 */
export class TriggerLookups {
  readonly #byRow = new Map<string, TriggerLookupSql & { columns: string[] }>();

  add(target: LookupTarget & { readonly via: string }): string {
    const row = [target.relation, target.key, target.via].join("\u0000");
    const known = this.#byRow.get(row);

    if (known) {
      if (!known.columns.includes(target.select)) {
        known.columns.push(target.select);
      }

      return `${known.name}.${target.select}`;
    }

    const name = `lk_${String(this.#byRow.size)}`;
    this.#byRow.set(row, {
      name,
      relation: target.relation,
      key: target.key,
      columns: [target.select],
      via: target.via,
    });

    return `${name}.${target.select}`;
  }

  get list(): readonly TriggerLookupSql[] {
    return [...this.#byRow.values()];
  }
}

/** A trigger value as SQL on `rec`; each lookup becomes a variable in `lookups`. */
export function triggerValueSql(
  tables: Readonly<Record<string, TableMeta | undefined>> | undefined,
  meta: TableMeta | undefined,
  value: AnyTriggerValue,
  where: string,
  lookups: TriggerLookups,
): string {
  if (typeof value === "string") {
    return `rec.${meta ? columnSql(meta, value, where) : sqlIdent(value)}`;
  }

  const target =
    tables && meta
      ? lookupTarget(tables, value, where)
      : rawLookupTarget(value);

  const via = triggerValueSql(tables, meta, value.via, where, lookups);

  return lookups.add({ ...target, via });
}

/** The columns of `when.changed` as an `old`/`new` comparison. */
export function changedSql(
  meta: TableMeta | undefined,
  changed: readonly string[],
  where: string,
): string {
  if (changed.length === 0) {
    throw new TypeError(`${where}: when.changed lists no columns`);
  }

  return changed
    .map((column) => {
      const db = meta
        ? columnSql(meta, column, "when.changed")
        : sqlIdent(column);

      return `old.${db} is distinct from new.${db}`;
    })
    .join(" or ");
}

/** The event name: one for every operation, one per operation, or the operation. */
export function eventSql(
  event: string | Readonly<Record<string, string | undefined>> | undefined,
): string {
  if (event === undefined) {
    return "tg_op";
  }

  if (typeof event === "string") {
    return sqlString(event);
  }

  const cases = Object.entries(event)
    .filter((entry): entry is [string, string] => entry[1] !== undefined)
    .map(
      ([operation, name]) =>
        ` when ${sqlString(operation.toUpperCase())} then ${sqlString(name)}`,
    );

  return cases.length === 0
    ? "tg_op"
    : `case tg_op${cases.join("")} else tg_op end`;
}
