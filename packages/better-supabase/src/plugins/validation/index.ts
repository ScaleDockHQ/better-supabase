import type { MutationOp } from "../../ir/types.ts";
import type { TableMeta } from "../../schema/types.ts";

import {
  DbException,
  dbError,
  type ValidationIssue,
} from "../../core/errors.ts";
import { definePlugin, type Plugin } from "../../core/plugin.ts";
import { type StandardSchemaV1, validate } from "../../core/standard.ts";
import { decodeValue, encodeValue } from "../../ir/wire.ts";
import { toApp, toDb } from "../shared.ts";

export interface TableValidators {
  /** Validates inserts and upserts, with app-cased keys. */
  readonly insert?: StandardSchemaV1;
  /** Validates update patches, with app-cased keys. */
  readonly update?: StandardSchemaV1;
}

export interface ValidationOptions {
  /**
   * Validators per table key. The `validators` export of a generated
   * `zod()` or `valibot()` module fits as is.
   */
  readonly schemas: Readonly<Record<string, TableValidators>>;
}

/**
 * Rows reach plugins in wire form (ISO text, decimal text), while generated
 * validators expect the column codecs' app values (Temporal, `bigint`).
 */
function decoded(
  table: TableMeta,
  row: Readonly<Record<string, unknown>>,
): Record<string, unknown> {
  const app = toApp(table, row);
  for (const [name, value] of Object.entries(app)) {
    const codec = table.columns[name]?.codec;
    if (codec === undefined || typeof value !== "string") continue;
    try {
      app[name] = decodeValue(codec, value);
    } catch {
      // Malformed text stays as it is, so the validator reports it.
    }
  }
  return app;
}

function encoded(row: Record<string, unknown>): Record<string, unknown> {
  for (const [name, value] of Object.entries(row))
    row[name] = encodeValue(value);
  return row;
}

async function check(
  schema: StandardSchemaV1,
  table: TableMeta,
  row: Readonly<Record<string, unknown>>,
  label: string,
  index: number | undefined,
): Promise<Record<string, unknown>> {
  const result = await validate(schema, decoded(table, row), label);
  if (result.ok) {
    const output = result.data;
    // SAFETY: the condition narrows output to a non-null object, and schemas
    // for rows output records.
    return typeof output === "object" && output !== null
      ? encoded(toDb(table, output as Record<string, unknown>))
      : { ...row };
  }
  const error = result.error;
  if (index === undefined || error.kind !== "validation")
    throw new DbException(error);
  const issues: ValidationIssue[] = error.issues.map((issue) => ({
    message: issue.message,
    path: [index, ...(issue.path ?? [])],
  }));
  throw new DbException(dbError("validation", error.message, { issues }));
}

/**
 * Validates writes with Standard Schema validators (zod, valibot, arktype,
 * ...). Runs after other plugins (`enforce: 'post'`), so it sees the tenant,
 * timestamp and actor columns they fill. Failures become `validation` errors
 * (422) with issue paths; bulk writes prefix the row index.
 */
export function validation(options: ValidationOptions): Plugin<"validation"> {
  return definePlugin({
    name: "validation",
    enforce: "post",
    async beforeMutation(op, { table }): Promise<MutationOp> {
      const validators = options.schemas[table.key];
      if (!validators) return op;
      switch (op.kind) {
        case "insert": {
          const schema = validators.insert;
          if (!schema) return op;
          const many = op.rows.length > 1;
          const rows = await Promise.all(
            op.rows.map((row, index) =>
              check(
                schema,
                table,
                row,
                `${table.key} insert`,
                many ? index : undefined,
              ),
            ),
          );
          return { ...op, rows };
        }
        case "update": {
          const schema = validators.update;
          if (!schema) return op;
          return {
            ...op,
            set: await check(
              schema,
              table,
              op.set,
              `${table.key} update`,
              undefined,
            ),
          };
        }
        case "delete":
          return op;
        default: {
          const exhaustive: never = op;
          return exhaustive;
        }
      }
    },
  });
}
