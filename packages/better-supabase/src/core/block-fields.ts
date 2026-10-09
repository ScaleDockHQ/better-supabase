import type { StandardSchemaV1 } from "./standard.ts";

import { dbError, type ValidationIssue } from "./errors.ts";
import { err, ok, type Result } from "./result.ts";
import { toIssues } from "./standard.ts";

/** The fields a `fields` schema adds, or none when the block has no schema. */
export type FieldsOf<S> =
  S extends StandardSchemaV1<unknown, infer O>
    ? O extends object
      ? O
      : never
    : Record<never, never>;

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
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

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
  return {
    async read(row) {
      if (schema === undefined) {
        // SAFETY: without a schema T is the empty field set.
        return ok(row as typeof row & T);
      }
      const outcome = await run(schema, row);
      if (outcome.issues) return invalid(label, toIssues(outcome.issues));
      if (!isObject(outcome.value)) {
        return invalid(label, [{ message: "fields must parse to an object" }]);
      }
      // SAFETY: the schema's output, which T describes, is merged over the row.
      return ok({ ...row, ...outcome.value } as typeof row & T);
    },
    async write(attrs) {
      if (schema === undefined) return ok(attrs);
      const outcome = await run(schema, attrs);
      if (!outcome.issues) {
        if (!isObject(outcome.value)) return ok(attrs);
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
      if (relevant.length === 0) return ok(attrs);
      return invalid(label, relevant);
    },
  };
}
