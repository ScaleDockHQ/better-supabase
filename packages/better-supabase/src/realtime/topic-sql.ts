import type { TableMeta } from "../schema/types.ts";

import { sqlIdent, sqlString } from "../core/template.ts";

export type AnyTriggerValue =
  | string
  | {
      readonly from: string;
      readonly via: AnyTriggerValue;
      readonly select: string;
      readonly key?: string;
    };

function columnSql(meta: TableMeta, column: string, where: string): string {
  const db = meta.columns[column]?.db;
  if (!db)
    throw new TypeError(
      `defineTopic: no column for ${where} on "${meta.key}" ("${column}")`,
    );
  return sqlIdent(db);
}

/** A trigger value as SQL on `rec`, with one subquery per lookup. */
export function triggerValueSql(
  tables: Readonly<Record<string, TableMeta | undefined>>,
  meta: TableMeta,
  value: AnyTriggerValue,
  where: string,
  depth = 0,
): string {
  if (typeof value === "string") return `rec.${columnSql(meta, value, where)}`;
  const joined = tables[value.from];
  if (!joined)
    throw new TypeError(
      `defineTopic: unknown table "${value.from}" for ${where}`,
    );
  const key =
    value.key ??
    (joined.primaryKey.length === 1 ? joined.primaryKey[0] : undefined);
  if (key === undefined)
    throw new TypeError(
      `defineTopic: "${value.from}" has no single-column primary key; name its key for ${where}`,
    );
  const alias = `j${String(depth)}`;
  const via = triggerValueSql(tables, meta, value.via, where, depth + 1);
  return `(select ${alias}.${columnSql(joined, value.select, where)} from ${sqlIdent(joined.schema)}.${sqlIdent(joined.name)} ${alias} where ${alias}.${columnSql(joined, key, where)} = ${via} limit 1)`;
}

/** The event name: one for every operation, one per operation, or the operation. */
export function eventSql(
  event: string | Readonly<Record<string, string | undefined>> | undefined,
): string {
  if (event === undefined) return "tg_op";
  if (typeof event === "string") return sqlString(event);
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
