import type { ColumnMeta } from "../schema/types.ts";
import type { FieldSpec, ScalarKind } from "./table-json-schema.ts";

const INTEGER = new Set(["int2", "int4", "int8"]);

const NUMBER = new Set(["float4", "float8", "numeric", "oid", "money"]);

/**
 * Types PostgREST returns as strings. Named here so an unmapped type is
 * `unknown` instead of a guess. A padded string, not a `Set`: this list ships
 * in the server JSON Schema chunk, and the spaces keep `time` from matching
 * `timestamp`.
 */
const TEXT =
  " text varchar bpchar char name citext vector halfvec sparsevec tsvector tsquery inet cidr macaddr macaddr8 interval time timetz timestamp int4range int8range numrange tsrange tstzrange daterange int4multirange int8multirange nummultirange tsmultirange tstzmultirange datemultirange bytea xml bit varbit point line lseg box path polygon circle jsonpath ";

const JSON = new Set(["json", "jsonb", "geometry", "geography"]);

/**
 * The scalar a column validates as, after its codec. Composite attributes are
 * not a scalar: `columnField` reads `column.fields`. An unmapped type is
 * `unknown`. `record` and `void` are `unknown` too, and they are not unmapped.
 */
export function columnKind(column: ColumnMeta): ScalarKind {
  if (column.enum) {
    return { kind: "enum", values: column.enum };
  }

  if (column.json || JSON.has(column.type)) {
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

  if (column.type === "timestamptz") {
    return { kind: "datetime" };
  }

  if (column.type === "date") {
    return { kind: "date" };
  }

  if (column.type === "record" || column.type === "void") {
    return { kind: "unknown" };
  }

  if (TEXT.includes(` ${column.type} `)) {
    return { kind: "string" };
  }

  return { kind: "unknown" };
}

/**
 * True when `gen` should say it could not map this type. `record` and `void`
 * are mapped.
 */
export function unmappedType(type: string): boolean {
  if (type === "record" || type === "void") {
    return false;
  }

  return columnKind({ db: "", type }).kind === "unknown";
}

/** Every scalar in a column, including the attributes of a composite. */
export function columnKinds(column: ColumnMeta): ScalarKind[] {
  if (column.fields) {
    return Object.values(column.fields).flatMap(columnKinds);
  }

  return [columnKind(column)];
}

function boundsOf(
  column: ColumnMeta,
): Pick<
  FieldSpec,
  | "minimum"
  | "exclusiveMinimum"
  | "maximum"
  | "exclusiveMaximum"
  | "minLength"
  | "maxLength"
> {
  return {
    ...(column.minimum === undefined ? {} : { minimum: column.minimum }),
    ...(column.exclusiveMinimum === undefined
      ? {}
      : { exclusiveMinimum: column.exclusiveMinimum }),
    ...(column.maximum === undefined ? {} : { maximum: column.maximum }),
    ...(column.exclusiveMaximum === undefined
      ? {}
      : { exclusiveMaximum: column.exclusiveMaximum }),
    ...(column.minLength === undefined ? {} : { minLength: column.minLength }),
    ...(column.maxLength === undefined ? {} : { maxLength: column.maxLength }),
  };
}

/**
 * The field a column validates as, including composite attributes, null and
 * arrays. Domain CHECK bounds travel with the column.
 */
export function columnField(column: ColumnMeta): FieldSpec {
  const spec = column.fields
    ? {
        kind: "object" as const,
        fields: Object.fromEntries(
          Object.entries(column.fields).map(([name, nested]) => [
            name,
            columnField(nested),
          ]),
        ),
      }
    : columnKind(column);

  return {
    ...spec,
    ...(column.nullable ? { nullable: true } : {}),
    ...(column.array ? { array: true } : {}),
    ...boundsOf(column),
  };
}
