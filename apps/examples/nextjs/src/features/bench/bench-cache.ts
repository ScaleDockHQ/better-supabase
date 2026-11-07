export const SCOPE_COUNT = 12;

export type ScopeVariant = "plain" | "session";

/** `plain` reads the request in every scope; `session` resolves a handle. */
export function scopeVariant(
  value: string | string[] | undefined,
): ScopeVariant {
  return value === "session" ? "session" : "plain";
}
