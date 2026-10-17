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
 * The receive condition for a topic's instance permission. With the
 * provider's `permitted` template it asks about the instance in the topic
 * (`{permission}`, `{id}` and `{tenant}` as text, `{resource}` as a text
 * literal, `{scope}` unquoted). Without one it falls back to the access
 * contract's tenant check, `tenant_ids_with(permission)` on the tenant
 * segment, and a topic without a tenant segment is refused.
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

function columnSql(meta: TableMeta, column: string, where: string): string {
  const db = meta.columns[column]?.db;
  if (!db) {
    throw new TypeError(
      `defineTopic: no column for ${where} on "${meta.key}" ("${column}")`,
    );
  }
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
  if (typeof value === "string") {
    return `rec.${columnSql(meta, value, where)}`;
  }
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
  const alias = `j${String(depth)}`;
  const via = triggerValueSql(tables, meta, value.via, where, depth + 1);
  return `(select ${alias}.${columnSql(joined, value.select, where)} from ${sqlIdent(joined.schema)}.${sqlIdent(joined.name)} ${alias} where ${alias}.${columnSql(joined, key, where)} = ${via} limit 1)`;
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
