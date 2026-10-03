import type { StandardSchemaV1 } from "@standard-schema/spec";

import { dbError, type ValidationIssue } from "./errors.ts";
import { err, ok, type Result } from "./result.ts";

export type { StandardSchemaV1 };

/** Validates with any Standard Schema (zod, valibot, arktype, ...). */
export async function validate<S extends StandardSchemaV1>(
  schema: S,
  value: unknown,
  label = "value",
): Promise<Result<StandardSchemaV1.InferOutput<S>>> {
  let outcome = schema["~standard"].validate(value);
  if (outcome instanceof Promise) outcome = await outcome;
  if (outcome.issues) {
    return err(
      dbError("validation", `Invalid ${label}`, {
        issues: toIssues(outcome.issues),
      }),
    );
  }
  // SAFETY: a result without issues carries the schema's output type, which the
  // spec types as unknown here.
  return ok(outcome.value as StandardSchemaV1.InferOutput<S>);
}

function toIssues(
  issues: readonly StandardSchemaV1.Issue[],
): readonly ValidationIssue[] {
  return issues.map((issue) => {
    const path = issue.path?.map((segment) => {
      const key = typeof segment === "object" ? segment.key : segment;
      // DbError stays JSON-serializable, and JSON drops symbols.
      return typeof key === "symbol" ? String(key) : key;
    });
    return path && path.length > 0
      ? { message: issue.message, path }
      : { message: issue.message };
  });
}
