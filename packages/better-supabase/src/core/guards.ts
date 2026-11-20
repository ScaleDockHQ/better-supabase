/**
 * `Array.isArray` narrows `unknown` and readonly arrays to `any[]`; this keeps
 * the element type (or `unknown`).
 */
export function isList(value: unknown): value is readonly unknown[] {
  return Array.isArray(value);
}

/** A plain object: not null and not an array. */
export const isRecord = (
  value: unknown,
): value is Readonly<Record<string, unknown>> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

export function errorText(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }

  if (typeof error === "object" && error !== null && "message" in error) {
    return String(error.message);
  }

  return String(error);
}
