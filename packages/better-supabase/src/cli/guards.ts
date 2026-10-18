/**
 * A plain object: not null and not an array. The CLI keeps its own copy of
 * `core/guards.ts` because it reaches the library only through entry files.
 */
export const isRecord = (
  value: unknown,
): value is Readonly<Record<string, unknown>> =>
  typeof value === "object" && value !== null && !Array.isArray(value);
