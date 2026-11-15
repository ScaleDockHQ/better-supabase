/**
 * The entries of `value` that are not `undefined`. `exactOptionalPropertyTypes`
 * rejects an explicit `undefined` for an optional property, so an optional
 * input goes through this before it reaches a block API.
 */
export function present<T extends object>(
  value: T,
): { [K in keyof T]?: Exclude<T[K], undefined> } {
  // SAFETY: the entries are the own keys of `value` with their values, minus
  // those that are undefined, which is the mapped type above.
  return Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined),
  ) as { [K in keyof T]?: Exclude<T[K], undefined> };
}
