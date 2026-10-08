import type { DbError } from "../core/errors.ts";

/** The first message per top-level field of a `validation` error. */
export function fieldErrorsOf(
  error: DbError | undefined,
): Readonly<Partial<Record<string, string>>> {
  if (error?.kind !== "validation") return {};
  const fields: Partial<Record<string, string>> = {};
  for (const issue of error.issues) {
    const key = issue.path?.[0];
    if (typeof key === "string" && fields[key] === undefined)
      fields[key] = issue.message;
  }
  return fields;
}
