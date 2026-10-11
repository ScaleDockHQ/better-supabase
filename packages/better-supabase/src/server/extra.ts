/** `{ ...base, ...extra }` that keeps lazy getters lazy. */
export function withExtra<T extends object, X extends object>(
  base: T,
  extra: X,
): T & X {
  // SAFETY: the descriptors copy every property of base and extra, getters included.
  return Object.defineProperties(
    {},
    {
      ...Object.getOwnPropertyDescriptors(base),
      ...Object.getOwnPropertyDescriptors(extra),
    },
  ) as T & X;
}
