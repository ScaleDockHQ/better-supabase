import type {
  GeneratorBlock,
  GeneratorEntitySchemas,
  GeneratorFunction,
  GeneratorInput,
  GeneratorInputSchema,
} from "../config/index.ts";
import type { FieldSpec, ScalarKind } from "../core/table-json-schema.ts";

import { entityNames } from "../core/entity-naming.ts";
import {
  fieldDocs,
  fieldsFor,
  propertyKey,
  tableDocs,
  tableEntries,
  titleOf,
  variantsFor,
} from "./shared.ts";

/** A schema for a function's arguments or one of a block's inputs. */
export interface ExtraSchema {
  /** Export name: `listTasksArgs`, `taskInput`. */
  readonly name: string;
  readonly title: string;
  readonly description?: string;
  readonly fields: Readonly<Record<string, FieldSpec>>;
}

/** What a function returns, when it is a table row or a scalar. */
export interface ResultSchema {
  /** Export name: `listTasksResult`. */
  readonly name: string;
  readonly title: string;
  /** The function returns a set: the schema is an array. */
  readonly set: boolean;
  /** A single result may be `null`; for sets, each scalar item may be. */
  readonly nullable: boolean;
  readonly of:
    | { readonly kind: "row"; readonly table: string }
    | { readonly kind: "scalar"; readonly scalar: ScalarKind };
}

export interface ExtraSchemas {
  readonly inputs: readonly ExtraSchema[];
  readonly results: readonly ResultSchema[];
}

/** What `fieldMeta` says about one field, for forms. */
export interface FieldMeta {
  readonly label: string;
  readonly required: boolean;
  readonly options?: readonly string[];
  readonly minimum?: number;
  readonly exclusiveMinimum?: number;
  readonly maximum?: number;
  readonly exclusiveMaximum?: number;
  readonly minLength?: number;
  readonly maxLength?: number;
}

const INTEGER = new Set(["int2", "int4", "int8"]);
const NUMBER = new Set(["float4", "float8", "numeric", "oid", "money"]);

const KIND_SUFFIX: Readonly<Record<keyof GeneratorEntitySchemas, string>> = {
  input: "Input",
  change: "Change",
  listFilter: "ListFilter",
};

const ENTITY_SCHEMA_KINDS = ["input", "change", "listFilter"] as const;

const ROW_RESULT = /^Models\["([^"]+)"\]\['Row'\](\[\]| \| null)$/;

function lowerFirst(name: string): string {
  return name.charAt(0).toLowerCase() + name.slice(1);
}

function camel(name: string): string {
  return lowerFirst(
    name.replaceAll(/[_-]([a-zA-Z0-9])/g, (_, c: string) => c.toUpperCase()),
  );
}

/** `workItemId` and `work_item_id` → `Work item id`. */
export function labelOf(name: string): string {
  return titleOf(name.replaceAll(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase());
}

/** `(string | null)[]` → `string`. */
function elementType(tsType: string): string {
  return tsType
    .replace(/\[\]$/, "")
    .replace(/^\((.*)\)$/, "$1")
    .replace(/ \| null$/, "");
}

/**
 * The scalar kind of a function argument or result, from its Postgres type and
 * the TypeScript type `gen` wrote (which reflects the configured codecs).
 */
function typeScalar(
  pgType: string | undefined,
  tsType: string,
  values: readonly string[] | undefined,
): ScalarKind {
  if (values && values.length > 0) {
    return { kind: "enum", values };
  }

  switch (tsType) {
    case "Temporal.Instant": {
      return { kind: "instant" };
    }

    case "Temporal.PlainDateTime": {
      return { kind: "plainDateTime" };
    }

    case "bigint": {
      return { kind: "bigint" };
    }

    case "Json": {
      return { kind: "json" };
    }

    default: {
      break;
    }
  }

  const pg = pgType?.replace(/^_/, "");

  if (pg === "uuid") {
    return { kind: "uuid" };
  }

  if (pg !== undefined && INTEGER.has(pg) && tsType === "number") {
    return { kind: "integer" };
  }

  if (pg === "timestamptz" && tsType === "string") {
    return { kind: "datetime" };
  }

  if (pg === "date" && tsType === "string") {
    return { kind: "date" };
  }

  if (pg !== undefined && NUMBER.has(pg) && tsType === "number") {
    return { kind: "number" };
  }

  switch (tsType) {
    case "number": {
      return { kind: "number" };
    }

    case "boolean": {
      return { kind: "boolean" };
    }

    case "string": {
      return { kind: "string" };
    }

    default: {
      return { kind: "unknown" };
    }
  }
}

function argsSchema(
  fn: GeneratorFunction,
  input: GeneratorInput,
): ExtraSchema | undefined {
  if (fn.args.length === 0 || fn.args.some((arg) => arg.name === "")) {
    return undefined;
  }

  const meta = input.meta.functions[fn.key];
  const fields: Record<string, FieldSpec> = {};

  for (const arg of fn.args) {
    const pgType = meta?.args.find((each) => each.name === arg.name)?.type;
    const scalar = typeScalar(pgType, elementType(arg.tsType), arg.values);
    const spec: FieldSpec = { ...scalar };

    fields[arg.name] = {
      ...spec,
      ...(arg.tsType.endsWith("[]") ? { array: true } : {}),
      ...(arg.optional ? { optional: true } : {}),
    };
  }

  return { name: `${camel(fn.key)}Args`, title: `${fn.key} arguments`, fields };
}

function resultSchema(
  fn: GeneratorFunction,
  input: GeneratorInput,
): ResultSchema | undefined {
  const name = `${camel(fn.key)}Result`;
  const title = `${fn.key} result`;
  const row = ROW_RESULT.exec(fn.returns);

  if (row?.[1] !== undefined) {
    const set = row[2] === "[]";

    return {
      name,
      title,
      set,
      nullable: !set,
      of: { kind: "row", table: row[1] },
    };
  }

  if (fn.returns.startsWith("{")) {
    return undefined;
  }

  const element = fn.returnsSet
    ? fn.returns.replace(/\[\]$/, "").replace(/^\((.*)\)$/, "$1")
    : fn.returns;

  const scalar = typeScalar(
    input.meta.functions[fn.key]?.returns,
    elementType(element),
    undefined,
  );

  if (scalar.kind === "unknown") {
    return undefined;
  }

  return {
    name,
    title,
    set: fn.returnsSet,
    nullable: element.endsWith(" | null"),
    of: { kind: "scalar", scalar },
  };
}

function renamedInput(
  schema: GeneratorInputSchema,
  rename: (identifier: string) => string,
  name: string,
): ExtraSchema {
  return {
    name,
    title: rename(schema.title),
    fields: Object.fromEntries(
      Object.entries(schema.fields).map(([field, spec]) => [
        rename(field),
        spec,
      ]),
    ),
  };
}

function blockInputs(block: GeneratorBlock): ExtraSchema[] {
  const names = entityNames(
    block.entities
      .filter((entity) => entity.from.singular !== entity.to.singular)
      .map((entity) => ({ from: entity.from, to: entity.to })),
  );

  return block.entities.flatMap((entity) =>
    ENTITY_SCHEMA_KINDS.flatMap((kind) => {
      const schema = entity.schemas[kind];

      return schema === undefined
        ? []
        : [
            renamedInput(
              schema,
              (identifier) => names.rename(identifier),
              `${camel(entity.to.singular)}${KIND_SUFFIX[kind]}`,
            ),
          ];
    }),
  );
}

/**
 * The schemas beside the table ones: each function's arguments and result, and
 * each installed block's inputs under the names the config gives its entities.
 * Overloaded functions are left out: one schema can't pick a signature.
 */
export function extraSchemas(input: GeneratorInput): ExtraSchemas {
  const counts = new Map<string, number>();

  for (const fn of input.model.functions) {
    counts.set(fn.key, (counts.get(fn.key) ?? 0) + 1);
  }

  const functions = input.model.functions
    .filter((fn) => counts.get(fn.key) === 1)
    .toSorted((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));

  return {
    inputs: [
      ...functions.flatMap((fn) => {
        const schema = argsSchema(fn, input);

        return schema ? [schema] : [];
      }),
      ...input.model.blocks.flatMap((block) => blockInputs(block)),
    ],
    results: functions.flatMap((fn) => {
      const schema = resultSchema(fn, input);

      return schema ? [schema] : [];
    }),
  };
}

/** Every scalar kind the extra schemas use, for the Temporal guard import. */
export function extraKinds(extras: ExtraSchemas): ScalarKind["kind"][] {
  return [
    ...extras.inputs.flatMap((schema) =>
      Object.values(schema.fields).map((field) => field.kind),
    ),
    ...extras.results.flatMap((result) =>
      result.of.kind === "scalar" ? [result.of.scalar.kind] : [],
    ),
  ].filter((kind): kind is ScalarKind["kind"] => kind !== "custom");
}

/** The TypeScript type a field validates to. */
export function fieldType(spec: FieldSpec): string {
  let type = scalarType(spec);

  if (spec.array) {
    type = `${type.includes(" | ") ? `(${type})` : type}[]`;
  }

  return spec.nullable ? `${type} | null` : type;
}

function scalarType(spec: FieldSpec): string {
  switch (spec.kind) {
    case "uuid":
    case "string":
    case "datetime":
    case "date": {
      return "string";
    }

    case "integer":
    case "number": {
      return "number";
    }

    case "boolean": {
      return "boolean";
    }

    case "instant": {
      return "Temporal.Instant";
    }

    case "plainDate": {
      return "Temporal.PlainDate";
    }

    case "plainDateTime": {
      return "Temporal.PlainDateTime";
    }

    case "bigint": {
      return "bigint";
    }

    case "json": {
      return "Json";
    }

    case "enum": {
      return spec.values.map((value) => JSON.stringify(value)).join(" | ");
    }

    case "unknown":
    case "custom": {
      return "unknown";
    }

    default: {
      const exhaustive: never = spec;

      return exhaustive;
    }
  }
}

/** `{ title: string; estimate?: number | null }`. */
export function objectType(schema: ExtraSchema): string {
  const entries = Object.entries(schema.fields).map(
    ([name, spec]) =>
      `${propertyKey(name)}${spec.optional ? "?" : ""}: ${fieldType(spec)}`,
  );

  return entries.length === 0
    ? "Record<never, never>"
    : `{ ${entries.join("; ")} }`;
}

/** The TypeScript type a result schema validates to. */
export function resultType(result: ResultSchema): string {
  const item =
    result.of.kind === "row"
      ? `RowOf<'${result.of.table}'>`
      : fieldType({
          ...result.of.scalar,
          nullable: result.set && result.nullable,
        });

  if (result.set) {
    return `${item.includes(" | ") ? `(${item})` : item}[]`;
  }

  return result.nullable ? `${item} | null` : item;
}

function metaOf(name: string, spec: FieldSpec, label?: string): FieldMeta {
  return {
    label: label ?? labelOf(name),
    required: spec.optional !== true && spec.nullable !== true,
    ...(spec.kind === "enum" ? { options: spec.values } : {}),
    ...(spec.minimum === undefined ? {} : { minimum: spec.minimum }),
    ...(spec.exclusiveMinimum === undefined
      ? {}
      : { exclusiveMinimum: spec.exclusiveMinimum }),
    ...(spec.maximum === undefined ? {} : { maximum: spec.maximum }),
    ...(spec.exclusiveMaximum === undefined
      ? {}
      : { exclusiveMaximum: spec.exclusiveMaximum }),
    ...(spec.minLength === undefined ? {} : { minLength: spec.minLength }),
    ...(spec.maxLength === undefined ? {} : { maxLength: spec.maxLength }),
  };
}

/** A short one-line comment labels its column; anything longer is a description. */
function commentLabel(description: string | undefined): string | undefined {
  return description !== undefined &&
    description.length <= 60 &&
    !description.includes("\n")
    ? description.replace(/\.$/, "")
    : undefined;
}

/**
 * Form metadata by schema: every writable table's Insert fields, keyed by
 * table, and every extra input schema, keyed by its export name.
 */
export function fieldMeta(
  input: GeneratorInput,
  extras: ExtraSchemas,
): Readonly<Record<string, Readonly<Record<string, FieldMeta>>>> {
  const out: Record<string, Record<string, FieldMeta>> = {};

  for (const [key, table] of tableEntries(input)) {
    if (!variantsFor(table).includes("Insert")) {
      continue;
    }

    const docs = tableDocs(input, table);
    const fields: Record<string, FieldMeta> = {};

    for (const plan of fieldsFor(table, "Insert", input)) {
      const found = fieldDocs(docs, plan);

      const spec: FieldSpec = plan.customJson
        ? { kind: "custom" }
        : { ...plan.scalar };

      fields[plan.name] = metaOf(
        plan.column.db,
        {
          ...spec,
          ...found,
          ...(plan.optional ? { optional: true } : {}),
          ...(plan.nullable ? { nullable: true } : {}),
        },
        commentLabel(found.description),
      );
    }

    out[key] = fields;
  }

  for (const schema of extras.inputs) {
    out[schema.name] = Object.fromEntries(
      Object.entries(schema.fields).map(([name, spec]) => [
        name,
        metaOf(name, spec),
      ]),
    );
  }

  return out;
}

/** `export const fieldMeta = { ... } as const;` for the TypeScript generators. */
export function fieldMetaLines(
  input: GeneratorInput,
  extras: ExtraSchemas,
): string[] {
  const meta = fieldMeta(input, extras);

  const lines = [
    "",
    "/** Labels, required flags, options and bounds for each writable field, for forms. */",
    "export const fieldMeta = {",
  ];

  for (const [schema, fields] of Object.entries(meta)) {
    lines.push(`  ${propertyKey(schema)}: {`);

    for (const [name, field] of Object.entries(fields)) {
      lines.push(`    ${propertyKey(name)}: ${JSON.stringify(field)},`);
    }

    lines.push("  },");
  }

  lines.push("} as const;");

  return lines;
}
