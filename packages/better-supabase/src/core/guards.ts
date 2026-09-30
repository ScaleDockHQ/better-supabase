/**
 * `Array.isArray` narrows `unknown` and readonly arrays to `any[]`; this keeps
 * the element type (or `unknown`).
 */
export function isList(value: unknown): value is readonly unknown[] {
  return Array.isArray(value);
}
