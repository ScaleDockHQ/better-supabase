import type {
  FieldSpec,
  JsonSchema,
  ScalarKind,
} from "../core/table-json-schema.ts";
import type {
  FieldDocs,
  FieldPlan,
  SchemaSource,
  TableDocs,
  Variant,
} from "../generators/shared.ts";
import type { ColumnMeta, SchemaMeta, TableMeta } from "../schema/types.ts";

import { tableJsonSchema } from "../core/table-json-schema.ts";
import {
  fieldDocs,
  tableDocs,
  tableEntries,
  variantTitle,
  variantsFor,
} from "../generators/shared.ts";

const INTEGER = new Set(["int2", "int4", "int8"]);
const NUMBER = new Set(["float4", "float8", "numeric", "oid", "money"]);

// `timestamp` values have no offset, so they stay plain strings.
const DATETIME = new Set(["timestamptz"]);

/**
 * The column types the running OpenAPI and MCP documents used before composite
 * fields. `gen` classifies those separately. Keeping this copy here leaves the
 * larger classifier out of every server route.
 */
function scalarKind(column: ColumnMeta): ScalarKind {
  if (column.enum) {
    return { kind: "enum", values: column.enum };
  }

  if (column.json) {
    return { kind: "json" };
  }

  if (column.codec === "instant") {
    return { kind: "instant" };
  }

  if (column.codec === "plainDateTime") {
    return { kind: "plainDateTime" };
  }

  if (column.codec === "bigint") {
    return { kind: "bigint" };
  }

  if (column.codec === "string") {
    return { kind: "string" };
  }

  if (column.type === "uuid") {
    return { kind: "uuid" };
  }

  if (INTEGER.has(column.type)) {
    return { kind: "integer" };
  }

  if (NUMBER.has(column.type)) {
    return { kind: "number" };
  }

  if (column.type === "bool") {
    return { kind: "boolean" };
  }

  if (DATETIME.has(column.type)) {
    return { kind: "datetime" };
  }

  if (column.type === "date") {
    return { kind: "date" };
  }

  if (column.type === "record" || column.type === "void") {
    return { kind: "unknown" };
  }

  return { kind: "string" };
}

function fieldsFor(
  table: TableMeta,
  variant: Variant,
  input: SchemaSource,
): FieldPlan[] {
  const fields: FieldPlan[] = [];
  const { timestamps, actor, softDelete } = table.flags;

  const managed = new Set(
    [
      timestamps?.createdAt,
      timestamps?.updatedAt,
      actor?.createdBy,
      actor?.updatedBy,
      actor?.impersonatedBy,
      softDelete,
    ].filter((name): name is string => name !== undefined),
  );

  for (const [name, column] of Object.entries(table.columns)) {
    if (
      variant === "Insert" &&
      (column.generated || column.insertable === false)
    ) {
      continue;
    }

    if (
      variant === "Update" &&
      (column.generated || column.updatable === false)
    ) {
      continue;
    }

    fields.push({
      name,
      column,
      scalar: scalarKind(column),
      nullable: column.nullable === true,
      optional:
        variant === "Update" ||
        (variant === "Insert" &&
          (column.nullable === true || column.hasDefault === true)),
      customJson: Boolean(
        column.json &&
        (input.config.json[`${table.schema}.${table.name}.${column.db}`] ??
          input.config.json[`${table.name}.${column.db}`]),
      ),
      managed: managed.has(name),
    });
  }

  return fields;
}

function fieldOf(plan: FieldPlan, docs: FieldDocs): FieldSpec {
  return {
    ...(plan.customJson ? { kind: "custom" } : plan.scalar),
    ...(plan.nullable ? { nullable: true } : {}),
    ...(plan.optional ? { optional: true } : {}),
    ...(plan.column.array ? { array: true } : {}),
    ...(plan.managed ? { readOnly: true } : {}),
    ...docs,
  };
}

function withDeprecated(
  schema: JsonSchema,
  deprecated: boolean,
  columns: readonly string[],
): JsonSchema {
  if (!deprecated && columns.length === 0) {
    return schema;
  }

  const properties = schema["properties"];

  return {
    ...schema,
    ...(deprecated ? { deprecated: true } : {}),
    ...(columns.length > 0 && typeof properties === "object" && properties
      ? {
          properties: Object.fromEntries(
            Object.entries(properties).map(
              ([name, value]: [string, unknown]) => [
                name,
                columns.includes(name) && typeof value === "object" && value
                  ? { ...value, deprecated: true }
                  : value,
              ],
            ),
          ),
        }
      : {}),
  };
}

/**
 * The 2020-12 `$defs` for every table. The generator's `toJsonSchema` also
 * writes composite fields and function results. These routes only need tables.
 */
export function tableJsonDefs(
  meta: SchemaMeta,
  json: Readonly<Record<string, unknown>> = {},
): Readonly<Record<string, JsonSchema>> {
  const input: SchemaSource = { meta, config: { json } };
  const defs: Record<string, JsonSchema> = {};

  for (const [key, table] of tableEntries(input)) {
    const docs: TableDocs | undefined = tableDocs(input, table);
    const description = docs ? docs.description : table.description;

    for (const variant of variantsFor(table)) {
      const plans = fieldsFor(table, variant, input);

      const schema = tableJsonSchema({
        ...(docs ? { title: variantTitle(docs, variant) } : {}),
        ...(description === undefined ? {} : { description }),
        fields: Object.fromEntries(
          plans.map((plan) => {
            const spec = fieldOf(plan, fieldDocs(docs, plan));

            return [
              plan.name,
              docs || plan.column.description === undefined
                ? spec
                : { description: plan.column.description, ...spec },
            ];
          }),
        ),
      });

      defs[`${key}${variant}`] = withDeprecated(
        schema,
        table.deprecated === true,
        plans.filter((plan) => plan.column.deprecated).map((plan) => plan.name),
      );
    }
  }

  return defs;
}
