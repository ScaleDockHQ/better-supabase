import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

/** An entry insert's columns and values, and each value by column name. */
export interface AuditInsert {
  readonly columns: string;
  readonly values: string;
  readonly pairs: readonly (readonly [column: string, value: string])[];
}

/**
 * `sql.modules.audit.options.metadataColumns`: an adopted log's own columns
 * and the metadata key that fills each.
 */
export function metadataColumns(
  ctx: ModuleContext,
): readonly (readonly [column: string, key: string])[] {
  const where = "sql.modules.audit.options.metadataColumns";
  const configured = ctx.option("metadataColumns");
  if (configured === undefined) return [];
  if (typeof configured !== "object" || configured === null) {
    throw new TypeError(`${where} must map columns to metadata keys`);
  }
  if (ctx.manages) {
    throw new TypeError(
      `${where} fills an adopted log's own columns; set mode: "adopt" or keep the values in metadata`,
    );
  }
  const mapped = new Set(
    Object.values(ctx.config.columns["log"] ?? {}).filter(
      (column): column is string => typeof column === "string",
    ),
  );
  return Object.entries(configured).map(([column, key]) => {
    if (typeof key !== "string" || key === "") {
      throw new TypeError(`${where}.${column} must be a metadata key`);
    }
    if (mapped.has(column)) {
      throw new TypeError(
        `${where}.${column}: the column is mapped in sql.modules.audit.columns.log, so the module already fills it`,
      );
    }
    return [column, key] as const;
  });
}

/** The event's metadata as stored: without the mapped keys unless `keepMappedMetadata`. */
export function storedMetadata(
  ctx: ModuleContext,
  extra: readonly (readonly [column: string, key: string])[],
): string {
  if (extra.length === 0 || ctx.flag("keepMappedMetadata", false))
    return "coalesce(metadata, '{}')";
  const keys = [...new Set(extra.map(([, key]) => sqlString(key)))];
  return `coalesce(metadata, '{}') - array[${keys.join(", ")}]::text[]`;
}

/**
 * The entry insert. With metadata columns it runs as dynamic SQL that names
 * only the mapped columns whose key the metadata has, so an omitted key
 * leaves the column to its default.
 */
export function eventInsert(
  ctx: ModuleContext,
  insert: AuditInsert,
  extra: readonly (readonly [column: string, key: string])[],
): string {
  const log = ctx.table("log");
  const id = ctx.col("log", "id");
  if (extra.length === 0) {
    return `
  insert into ${log} (${insert.columns})
  values (
    ${insert.values}
  )
  returning ${id} into entry_id;`;
  }
  const pairs = insert.pairs.map(
    ([column, value]) => `${sqlString(column)}, ${value}`,
  );
  const chunks: string[] = [];
  for (let index = 0; index < pairs.length; index += 40)
    chunks.push(
      `pg_catalog.jsonb_build_object(\n    ${pairs.slice(index, index + 40).join(",\n    ")}\n  )`,
    );
  const mapped = extra.map(
    ([column, key]) =>
      `\n    || case when audit_event.metadata ? ${sqlString(key)} then pg_catalog.jsonb_build_object(${sqlString(column)}, audit_event.metadata -> ${sqlString(key)}) else '{}'::jsonb end`,
  );
  const target = log.replaceAll("%", "%%");
  const statement = `insert into ${target} (%s) select %s from pg_catalog.jsonb_populate_record(null::${target}, $1) returning ${id.replaceAll("%", "%%")}`;
  return `
  entry_row := ${chunks.join("\n  || ")}${mapped.join("")};
  select pg_catalog.string_agg(pg_catalog.quote_ident(k), ', ') into entry_columns
  from pg_catalog.jsonb_object_keys(entry_row) k;
  execute pg_catalog.format(${sqlString(statement)}, entry_columns, entry_columns)
    using entry_row into entry_id;`;
}
