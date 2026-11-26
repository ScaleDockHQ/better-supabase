import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { ReadSet, ReadSetResult } from "../core/read-set.ts";
import type { InferResult, QuerySpec, ReadSetEntry } from "../core/spec.ts";
import type { FieldSpec, ScalarKind } from "../core/table-json-schema.ts";
import type { TableSchema } from "../core/table-schema.ts";
import type { Selection } from "../ir/types.ts";
import type {
  Codec,
  FunctionMeta,
  SchemaMeta,
  TableMeta,
} from "../schema/types.ts";

import { columnField } from "../core/column-kind.ts";
import { isRecord } from "../core/guards.ts";
import { isFunctionSpec, isQuerySpec } from "../core/spec.ts";
import { tableSchema, valueSchema } from "../core/table-schema.ts";
import { builderFor, invalidRequest } from "../ir/build.ts";
import { rpcReturnSchema } from "../schema/rpc-returns.ts";

export interface ResultSchemaOptions {
  /**
   * What to do with a key the result does not name. `strip` (the default) drops
   * it. `reject` fails the value.
   */
  readonly unknownKeys?: "strip" | "reject";
}

/**
 * A Standard Schema for the value `db.$many(readSet, params)` returns. It
 * checks each column, not only the shape `readSet.parse` checks. Nothing calls
 * it unless the app does.
 */
export function resultSchema<S extends ReadSet>(
  readSet: S,
  options?: ResultSchemaOptions,
): TableSchema<ReadSetResult<S>> {
  const meta = readSet.definition.schema.meta;
  const fields: Record<string, FieldSpec> = {};

  for (const [key, spec] of Object.entries(readSet.specs)) {
    fields[key] = entryField(meta, spec, options);
  }

  return tableSchema<ReadSetResult<S>>({ fields, ...unknownKeys(options) });
}

/**
 * A Standard Schema for the value `db.$run(spec)` returns. The same rules as
 * `resultSchema` for one read.
 */
export function specResultSchema<S extends QuerySpec>(
  meta: SchemaMeta,
  spec: S,
  options?: ResultSchemaOptions,
): TableSchema<InferResult<S>> {
  return valueSchema<InferResult<S>>(
    queryField(meta, spec, options),
    unknownKeys(options),
  );
}

function unknownKeys(options: ResultSchemaOptions | undefined): {
  readonly unknownKeys?: "strip" | "reject";
} {
  return options?.unknownKeys === undefined
    ? {}
    : { unknownKeys: options.unknownKeys };
}

function entryField(
  meta: SchemaMeta,
  spec: ReadSetEntry,
  options: ResultSchemaOptions | undefined,
): FieldSpec {
  const field = isQuerySpec(spec)
    ? queryField(meta, spec, options)
    : isFunctionSpec(spec)
      ? functionField(meta, spec.name, options)
      : { kind: "unknown" as const };

  return spec.gate ? { ...field, nullable: true } : field;
}

function queryField(
  meta: SchemaMeta,
  spec: QuerySpec,
  options: ResultSchemaOptions | undefined,
): FieldSpec {
  const table = requireTable(meta, spec.table);
  const args = specOptions(spec);

  switch (spec.method) {
    case "list": {
      return {
        kind: "custom",
        array: true,
        schema: rowSchema(meta, table, args, options),
      };
    }

    case "get": {
      return {
        kind: "custom",
        nullable: true,
        schema: rowSchema(meta, table, args, options),
      };
    }

    case "count": {
      return { kind: "integer" };
    }

    case "page": {
      return pageField(meta, table, args, options);
    }

    case "aggregate": {
      return aggregateField(meta, table, args);
    }

    default: {
      const exhaustive: never = spec.method;

      return exhaustive;
    }
  }
}

function functionField(
  meta: SchemaMeta,
  name: string,
  options: ResultSchemaOptions | undefined,
): FieldSpec {
  const registered = rpcReturnSchema(name);

  if (registered) {
    const fn = meta.functions[name];

    return {
      kind: "custom",
      schema: registered,
      ...(fn?.returnsSet ? { array: true } : {}),
    };
  }

  const fn = meta.functions[name];

  if (!fn) {
    return { kind: "unknown" };
  }

  return functionResultField(meta, fn, options);
}

function functionResultField(
  meta: SchemaMeta,
  fn: FunctionMeta,
  options: ResultSchemaOptions | undefined,
): FieldSpec {
  const result = fn.result;

  if (result && "table" in result) {
    const row = rowSchema(meta, requireTable(meta, result.table), {}, options);

    return fn.returnsSet
      ? { kind: "custom", array: true, schema: row }
      : { kind: "custom", nullable: true, schema: row };
  }

  if (result && "columns" in result) {
    const fields: Record<string, FieldSpec> = {};

    for (const column of result.columns) {
      fields[column.name ?? column.db] = {
        ...(column.codec
          ? codecField(column.codec)
          : { kind: "custom" as const }),
        nullable: true,
      };
    }

    const object: FieldSpec = { kind: "object", fields };

    return fn.returnsSet
      ? { ...object, array: true }
      : { ...object, nullable: true };
  }

  return { kind: "unknown" };
}

function codecField(codec: Codec | undefined): ScalarKind {
  switch (codec) {
    case "instant": {
      return { kind: "instant" };
    }

    case "plainDateTime": {
      return { kind: "plainDateTime" };
    }

    case "bigint": {
      return { kind: "bigint" };
    }

    case "string":
    case "utcString": {
      return { kind: "string" };
    }

    case undefined: {
      return { kind: "unknown" };
    }

    default: {
      const exhaustive: never = codec;

      return exhaustive;
    }
  }
}

function pageField(
  meta: SchemaMeta,
  table: TableMeta,
  args: Readonly<Record<string, unknown>>,
  options: ResultSchemaOptions | undefined,
): FieldSpec {
  const items: FieldSpec = {
    kind: "custom",
    array: true,
    schema: rowSchema(meta, table, args, options),
  };

  const count = counted(args);

  const number: FieldSpec = count
    ? { kind: "integer" }
    : { kind: "integer", nullable: true };

  if (args["after"] !== undefined) {
    return {
      kind: "object",
      fields: {
        items,
        nextCursor: { kind: "string", nullable: true },
        hasMore: { kind: "boolean" },
        ...(count
          ? {
              total: { kind: "integer" },
              capped: { kind: "boolean", optional: true },
            }
          : {}),
      },
    };
  }

  return {
    kind: "object",
    fields: {
      items,
      page: {
        kind: "object",
        fields: {
          number: { kind: "integer" },
          size: { kind: "integer" },
          total: number,
          pages: number,
          hasMore: { kind: "boolean" },
          capped: { kind: "boolean", optional: true },
        },
      },
    },
  };
}

function aggregateField(
  meta: SchemaMeta,
  table: TableMeta,
  args: Readonly<Record<string, unknown>>,
): FieldSpec {
  builderFor(meta).aggregation(table, args);

  const fields: Record<string, FieldSpec> = {};
  const groupBy = args["groupBy"];

  if (Array.isArray(groupBy)) {
    for (const name of groupBy) {
      const column = table.columns[String(name)];

      if (column) {
        fields[String(name)] = columnField(column);
      }
    }
  }

  if (args["_count"] === true) {
    fields["_count"] = { kind: "integer" };
  }

  for (const key of ["_sum", "_avg", "_min", "_max"] as const) {
    const value = args[key];

    if (!isRecord(value)) {
      continue;
    }

    const measures: Record<string, FieldSpec> = {};

    for (const [alias, enabled] of Object.entries(value)) {
      if (enabled) {
        measures[alias] = { kind: "number", nullable: true };
      }
    }

    if (Object.keys(measures).length > 0) {
      fields[key] = { kind: "object", fields: measures };
    }
  }

  const object: FieldSpec = { kind: "object", fields };

  return Array.isArray(groupBy) ? { ...object, array: true } : object;
}

function counted(args: Readonly<Record<string, unknown>>): boolean {
  const count = args["count"];

  return (
    args["withCount"] === true ||
    count === "exact" ||
    count === "planned" ||
    count === "estimated"
  );
}

function rowSchema(
  meta: SchemaMeta,
  table: TableMeta,
  args: Readonly<Record<string, unknown>>,
  options: ResultSchemaOptions | undefined,
): StandardSchemaV1 {
  const select = stringList(args["select"]);
  const include = args["include"];

  const selection = builderFor(meta).selection(
    table,
    select,
    include === undefined || isRecord(include) ? include : undefined,
  );

  return tableSchema({
    fields: fieldsOf(table, selection, options),
    ...unknownKeys(options),
  });
}

function fieldsOf(
  table: TableMeta,
  selection: Selection,
  options: ResultSchemaOptions | undefined,
): Record<string, FieldSpec> {
  const fields: Record<string, FieldSpec> = {};

  for (const column of selection.columns) {
    const metaColumn = table.columns[column.alias];

    if (!metaColumn) {
      continue;
    }

    const spec = columnField(metaColumn);

    fields[column.alias] = {
      ...spec,
      optional: false,
      nullable: metaColumn.nullable === true,
    };
  }

  const counts: Record<string, FieldSpec> = {};
  const measures: Record<string, Record<string, FieldSpec>> = {};

  for (const include of selection.includes) {
    if (include.count !== undefined) {
      counts[include.count] = { kind: "integer" };
      continue;
    }

    if (include.aggregate) {
      let bucket = measures[include.aggregate.fn];

      if (!bucket) {
        bucket = {};
        measures[include.aggregate.fn] = bucket;
      }

      bucket[include.aggregate.name] = { kind: "number", nullable: true };
      continue;
    }

    const nested = tableSchema({
      fields: fieldsOf(include.target, include.selection, options),
      ...unknownKeys(options),
    });

    const many = include.relation.kind === "many";

    fields[include.alias] = {
      kind: "custom",
      schema: nested,
      ...(many ? { array: true } : {}),
      ...(!many && include.relation.nullable ? { nullable: true } : {}),
    };
  }

  if (Object.keys(counts).length > 0) {
    fields["_count"] = { kind: "object", fields: counts };
  }

  for (const [fn, bucket] of Object.entries(measures)) {
    fields[`_${fn}`] = { kind: "object", fields: bucket };
  }

  return fields;
}

function requireTable(meta: SchemaMeta, key: string): TableMeta {
  const table = meta.tables[key];

  if (table) {
    return table;
  }

  invalidRequest(
    meta.tableGetters?.[key] === undefined
      ? `Unknown table "${key}"`
      : `${key} is not loaded`,
    key,
  );
}

function specOptions(spec: QuerySpec): Readonly<Record<string, unknown>> {
  const value = spec.method === "get" ? spec.args[1] : spec.args[0];
  const options = isRecord(value) ? value : {};
  const key = spec.method === "get" ? spec.args[0] : undefined;

  if (isRecord(key) && "where" in key) {
    return { ...options, where: key["where"] };
  }

  return options;
}

function stringList(value: unknown): readonly string[] | undefined {
  if (
    !Array.isArray(value) ||
    !value.every((item) => typeof item === "string")
  ) {
    return undefined;
  }

  return value;
}
