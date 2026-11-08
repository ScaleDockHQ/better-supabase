import type { StandardSchemaV1 } from "./standard.ts";

import { isRecord } from "./guards.ts";

/** The TypeScript type of one SQL column type, by its leading type name. */
type BaseOf<T extends string> = T extends `${infer Head} not null${string}`
  ? BaseOf<Head>
  : T extends `${infer Head} default${string}`
    ? BaseOf<Head>
    : T extends `${infer Head}[]`
      ? BaseOf<Head>[]
      : Lowercase<T> extends
            | "text"
            | "varchar"
            | "citext"
            | "uuid"
            | "date"
            | "timestamptz"
            | "timestamp"
            | "time"
            | "interval"
            | "int8"
            | "bigint"
            | "numeric"
            | "money"
        ? string
        : Lowercase<T> extends
              | "int2"
              | "int4"
              | "integer"
              | "smallint"
              | "float4"
              | "float8"
              | "real"
              | "double precision"
          ? number
          : Lowercase<T> extends "boolean" | "bool"
            ? boolean
            : unknown;

type Required_<T extends string> =
  Lowercase<T> extends `${string}not null${string}` ? true : false;

type Defaulted<T extends string> =
  Lowercase<T> extends `${string} default${string}` ? true : false;

/** A key the caller must send: `not null` and no database default. */
type NeededOnInput<T extends string> =
  Required_<T> extends true
    ? Defaulted<T> extends true
      ? false
      : true
    : false;

/**
 * What `columnsSchema` accepts: a column with `not null` and no `default` is a
 * required key. Any other column is optional, because the database fills a
 * default and a nullable column may be `null`.
 */
export type ColumnsInput<C extends Readonly<Record<string, string>>> = {
  readonly [
    K in keyof C as NeededOnInput<C[K]> extends true ? K : never
  ]: BaseOf<C[K]>;
} & {
  readonly [
    K in keyof C as NeededOnInput<C[K]> extends true ? never : K
  ]?: BaseOf<C[K]> | null;
};

/**
 * What `columnsSchema` returns: a column with `not null` is a required key
 * (also when it has a default), any other column is optional and may be
 * `null`.
 */
export type ColumnsOutput<C extends Readonly<Record<string, string>>> = {
  readonly [K in keyof C as Required_<C[K]> extends true ? K : never]: BaseOf<
    C[K]
  >;
} & {
  readonly [K in keyof C as Required_<C[K]> extends true ? never : K]?: BaseOf<
    C[K]
  > | null;
};

type Check = (value: unknown) => boolean;

const TEXTUAL = new Set([
  "text",
  "varchar",
  "char",
  "citext",
  "uuid",
  "date",
  "timestamptz",
  "timestamp",
  "time",
  "timetz",
  "interval",
  "int8",
  "bigint",
  "numeric",
  "decimal",
  "money",
]);

const NUMERIC = new Set([
  "int2",
  "int4",
  "integer",
  "smallint",
  "float4",
  "float8",
  "real",
  "double precision",
]);

const isString: Check = (value) => typeof value === "string";

const isNumber: Check = (value) =>
  typeof value === "number" && Number.isFinite(value);

const isBoolean: Check = (value) => typeof value === "boolean";
const anything: Check = () => true;

/** The type name before `not null`, `default` or a size such as `(10, 2)`. */
function typeName(sql: string): string {
  const lower = sql.toLowerCase().trim();

  return lower
    .replace(/\s+(not null|null|default|check|references|generated)\b.*$/u, "")
    .replaceAll(/\(.*?\)/gu, "")
    .replaceAll("[]", "")
    .trim();
}

/**
 * The check for a column's SQL type. `int8` and `numeric` are strings, as every
 * amount is (ADR 0037); an array is checked element by element.
 */
function checkOf(sql: string): Check {
  const name = typeName(sql);

  const base = TEXTUAL.has(name)
    ? isString
    : NUMERIC.has(name)
      ? isNumber
      : name === "boolean" || name === "bool"
        ? isBoolean
        : anything;

  return /\[\]/u.test(sql)
    ? (value) => Array.isArray(value) && value.every((item) => base(item))
    : base;
}

interface Column {
  readonly check: Check;
  /** `not null`: `null` is refused. */
  readonly notNull: boolean;
  /** `not null` without a default: the key must be sent. */
  readonly required: boolean;
  readonly type: string;
}

/**
 * A Standard Schema for the extra columns of a block table (the columns your
 * schema files add), with no schema library. `gen` writes it into
 * `blocks.generated.ts`, so a block's `fields` type and check the columns the
 * config adds. Text, dates, `int8` and `numeric` are strings, `int2`, `int4`
 * and the floats are numbers, a column with `not null` is a required key and
 * the others may be missing or `null`. Keys the config doesn't list pass
 * through.
 */
export function columnsSchema<const C extends Readonly<Record<string, string>>>(
  columns: C,
): StandardSchemaV1<ColumnsInput<C>, ColumnsOutput<C>> {
  const specs = Object.entries(columns).map(
    ([key, type]): readonly [string, Column] => {
      const notNull = /\bnot\s+null\b/iu.test(type);

      return [
        key,
        {
          check: checkOf(type),
          notNull,
          required: notNull && !/\bdefault\b/iu.test(type),
          type,
        },
      ];
    },
  );

  return {
    "~standard": {
      version: 1,
      vendor: "better-supabase",
      validate: (value) => {
        if (!isRecord(value)) {
          return { issues: [{ message: "Expected an object" }] };
        }

        const issues: StandardSchemaV1.Issue[] = [];

        for (const [key, column] of specs) {
          const present = value[key];

          if (present === undefined || present === null) {
            if (present === undefined && column.required) {
              issues.push({ message: `${key} is required`, path: [key] });
            } else if (present === null && column.notNull) {
              issues.push({ message: `${key} can't be null`, path: [key] });
            }

            continue;
          }

          if (!column.check(present)) {
            issues.push({
              message: `${key} doesn't match its column type ${column.type}`,
              path: [key],
            });
          }
        }

        // SAFETY: with no issues, the keys `ColumnsOutput` types passed their checks.
        return issues.length > 0
          ? { issues }
          : { value: value as ColumnsOutput<C> };
      },
    },
  };
}
