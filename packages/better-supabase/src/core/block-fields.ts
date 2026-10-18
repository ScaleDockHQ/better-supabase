import type { StandardSchemaV1 } from "./standard.ts";

import { dbError, type ValidationIssue } from "./errors.ts";
import { isRecord } from "./guards.ts";
import { AsyncResult, err, ok, type Result } from "./result.ts";
import { toIssues } from "./standard.ts";

/** The fields a `fields` schema adds, or none when the block has no schema. */
export type FieldsOf<S> =
  S extends StandardSchemaV1<unknown, infer O>
    ? O extends object
      ? O
      : never
    : Record<never, never>;

/** The extra columns of a row, keyed by database name, typed by `F`. */
export type ExtraFields<F extends object = Record<never, never>> = Readonly<
  Record<string, unknown>
> &
  F;

/** A row whose extra columns a block read under `fields`. */
export interface WithExtraFields {
  readonly fields: Readonly<Record<string, unknown>>;
}

/**
 * Parses and validates the extra fields an app adds to a block's table,
 * with any Standard Schema (zod, valibot, arktype) for an object.
 */
export interface BlockFields<T extends object> {
  /**
   * Parses a row the block read: the schema's output replaces the fields it
   * covers, and the other fields stay as read. A row the schema rejects is
   * a `validation` error.
   */
  read<R extends object>(row: R): Promise<Result<R & T>>;
  /**
   * Validates the fields a write sets. Issues about fields the write leaves
   * out are ignored, so partial updates pass; the database applies its
   * defaults and `not null` checks. A rejected write is a `validation`
   * error, and nothing is sent to the database.
   */
  write<A extends object>(attrs: A): Promise<Result<A>>;
  /**
   * Parses the `fields` of a row the block read: the extra columns its SQL
   * returns under `fields`, keyed by database name.
   */
  readonly row: <R extends WithExtraFields>(
    row: R,
  ) => AsyncResult<R & { readonly fields: ExtraFields<T> }>;
  /** `row` for each row, stopping at the first rejected one. */
  readonly rows: <R extends WithExtraFields>(
    rows: readonly R[],
  ) => AsyncResult<(R & { readonly fields: ExtraFields<T> })[]>;
  /**
   * Validates the extra fields a write sets, as the jsonb argument the SQL
   * function takes; `undefined` without any, so the argument is left out.
   */
  readonly args: (
    fields: object | undefined,
  ) => AsyncResult<Readonly<Record<string, unknown>> | undefined>;
}

/** The extra columns a block row carries, by column name, typed by its `fields` schema. */
export type RowFields<F extends object> = Readonly<Record<string, unknown>> & F;

/** A row the block read, with its `fields` parsed. */
export type WithFields<
  R extends { readonly fields: object },
  F extends object,
> = Omit<R, "fields"> & { readonly fields: R["fields"] & F };

/** Parses the `fields` of one row with `fields.read`. */
export function readFields<
  R extends { readonly fields: object },
  F extends object,
>(fields: BlockFields<F>, row: R): AsyncResult<WithFields<R, F>> {
  return AsyncResult.from(() => fields.read(row.fields)).map((parsed) => ({
    ...row,
    fields: parsed,
  }));
}

/** Parses the `fields` of each row; the first rejected row fails the read. */
export function readAllFields<
  R extends { readonly fields: object },
  F extends object,
>(fields: BlockFields<F>, rows: readonly R[]): AsyncResult<WithFields<R, F>[]> {
  return AsyncResult.from(async () => {
    const out: WithFields<R, F>[] = [];

    for (const row of rows) {
      const parsed = await fields.read(row.fields);

      if (!parsed.ok) {
        return parsed;
      }

      out.push({ ...row, fields: parsed.data });
    }

    return ok(out);
  });
}

/**
 * Validates the `fields` a write sets with `fields.write`, then builds the
 * call. A write without fields skips the check and passes none.
 */
export function writeFields<F extends object, T>(
  fields: BlockFields<F>,
  values: Readonly<Record<string, unknown>> | undefined,
  then: (
    checked: Readonly<Record<string, unknown>> | undefined,
  ) => AsyncResult<T>,
): AsyncResult<T> {
  if (values === undefined) {
    return then(undefined);
  }

  return AsyncResult.from(() => fields.write({ ...values })).andThen(then);
}

/** The `fields` object of a row a block function returned, or none. */
export function rowFields(value: unknown): Readonly<Record<string, unknown>> {
  return isRecord(value) ? value : {};
}

async function run(
  schema: StandardSchemaV1,
  value: unknown,
): Promise<StandardSchemaV1.Result<unknown>> {
  return schema["~standard"].validate(value);
}

const invalid = (
  label: string,
  issues: readonly ValidationIssue[],
): Result<never> => err(dbError("validation", `Invalid ${label}`, { issues }));

/**
 * The `fields` helper block creators use. Without a schema, reads and
 * writes pass through unchanged.
 */
export function blockFields<T extends object = Record<never, never>>(
  schema: StandardSchemaV1 | undefined,
  label: string,
): BlockFields<T> {
  const fields: BlockFields<T> = {
    async read(row) {
      if (schema === undefined) {
        // SAFETY: without a schema T is the empty field set.
        return ok(row as typeof row & T);
      }

      const outcome = await run(schema, row);

      if (outcome.issues) {
        return invalid(label, toIssues(outcome.issues));
      }

      if (!isRecord(outcome.value)) {
        return invalid(label, [{ message: "fields must parse to an object" }]);
      }

      // SAFETY: the schema's output, which T describes, is merged over the row.
      return ok({ ...row, ...outcome.value } as typeof row & T);
    },
    async write(attrs) {
      if (schema === undefined) {
        return ok(attrs);
      }

      const outcome = await run(schema, attrs);

      if (!outcome.issues) {
        if (!isRecord(outcome.value)) {
          return ok(attrs);
        }

        const parsed = outcome.value;

        const picked = Object.fromEntries(
          Object.keys(attrs)
            .filter((key) => key in parsed)
            .map((key) => [key, parsed[key]]),
        );

        return ok({ ...attrs, ...picked });
      }

      const given = new Set(Object.keys(attrs));

      const relevant = toIssues(outcome.issues).filter((issue) => {
        const [first] = issue.path ?? [];

        return first === undefined || given.has(String(first));
      });

      // Every issue concerns a field the write leaves out: a partial update.
      if (relevant.length === 0) {
        return ok(attrs);
      }

      return invalid(label, relevant);
    },
    row: (row) =>
      AsyncResult.from(() => fields.read(row.fields)).map((parsed) => ({
        ...row,
        fields: parsed,
      })),
    rows: (rows) =>
      AsyncResult.from(async () => {
        const out: ((typeof rows)[number] & {
          readonly fields: ExtraFields<T>;
        })[] = [];

        for (const row of rows) {
          const parsed = await fields.row(row);

          if (!parsed.ok) {
            return parsed;
          }

          out.push(parsed.data);
        }

        return ok(out);
      }),
    args: (extra) =>
      AsyncResult.from(async () => {
        if (extra === undefined || Object.keys(extra).length === 0) {
          return ok(undefined);
        }

        const checked = await fields.write({ ...extra });

        return checked.ok ? ok(checked.data) : checked;
      }),
  };

  return fields;
}

/** The keys of a write the block doesn't type itself: its extra fields. */
export const extraOf = (
  input: object,
  known: ReadonlySet<string>,
): Record<string, unknown> =>
  Object.fromEntries(Object.entries(input).filter(([key]) => !known.has(key)));

/** The extra columns a block read returns under its `fields` key. */
const extraFieldsOf = (value: unknown): Record<string, unknown> =>
  isRecord(value) && isRecord(value["fields"]) ? value["fields"] : {};

/**
 * Parses the extra columns of `raw` (a row a block function returned) and
 * adds them to `row`, the block's typed row. The row's own keys win, so an
 * extra column never replaces one the block types.
 */
export async function withFields<R extends object, T extends object>(
  fields: BlockFields<T>,
  raw: unknown,
  row: R,
): Promise<Result<R & T>> {
  const parsed = await fields.read(extraFieldsOf(raw));

  if (!parsed.ok) {
    return parsed;
  }

  return ok({ ...parsed.data, ...row });
}

/** `withFields` over a list of pairs: the raw row and the typed row. */
export async function allWithFields<R extends object, T extends object>(
  fields: BlockFields<T>,
  rows: readonly (readonly [unknown, R])[],
): Promise<Result<(R & T)[]>> {
  const out: (R & T)[] = [];

  for (const [raw, row] of rows) {
    const parsed = await withFields(fields, raw, row);

    if (!parsed.ok) {
      return parsed;
    }

    out.push(parsed.data);
  }

  return ok(out);
}

/**
 * Validates the extra fields of a write: `{ fields }` to spread into
 * the call's arguments, or `{}` when the write sets none, so a module
 * without extra columns is called as before.
 */
export async function extraFieldsArg(
  fields: BlockFields<object>,
  extra: Readonly<Record<string, unknown>>,
): Promise<Result<{ readonly fields?: Readonly<Record<string, unknown>> }>> {
  if (Object.keys(extra).length === 0) {
    return ok({});
  }

  const valid = await fields.write(extra);

  return valid.ok ? ok({ fields: valid.data }) : valid;
}
